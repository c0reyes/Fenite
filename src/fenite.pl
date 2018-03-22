#!/usr/bin/perl

use strict;
use threads;
use Telegram::Bot;
use HTTP::Daemon;
use POSIX qw(strftime);
use Encode qw(encode);
use Data::Dumper;
use Google::Cloud::Speech;
use JSON;
use LWP::Simple;

use forks;
use forks::shared deadlock => {detect=> 1, resolve => 1};

use lib '.';
use Fenite qw(query update insert);

my @send_messages;
my @all;

my @mmgs = ();
my $op = "";
my @o = ();
my @mm = ();
my @r = ();
my $regex = "";
my %resp = ();

share(@mmgs);
share($regex);
share(%resp);
share(@send_messages);
share(@all);

# Bot
my $bot = new Telegram::Bot;

$SIG{CHLD} = 'IGNORE';

local $SIG{__WARN__} = sub {
    my $message = shift;
    print $message . "\n";
};

open(STDOUT, ">/dev/null");
open(STDERR, ">/dev/null");

sub sendmsg {
	my $chat = shift;
    my $msg = shift;
    push(@send_messages, $chat . "||" . $msg);
}

sub sendToChat {
    while(1) {
        if(@send_messages > 0) {
            my $m = shift(@send_messages);
            my @a = split(/\|\|/, $m);
            $bot->sendMessage([
                chat_id => $a[0],
                text => $a[1],
                parse_mode => 'Markdown',
                disable_web_page_preview => 'true'
            ]);
        }
        sleep(0.3);
    }
}

sub _load {
    # MMGs 
    undef @mmgs;
    @mmgs = ();
    @mmgs = query("select frase, type from fenite_frases order by random()");

    # Operadores
    undef @o;
    @o = ();
    @o = query("select codename from fenite_op");
    $op = join("|", @o);
    $op =~ s/\s\n|\n//g;

    # Regex
    undef $regex;
    @r = ();
    @r = query("select regex from fenite_regex");
    $regex = join("|", @r);
    $regex =~ s/\s\n|\n//g;

    # Resp
    my @re = ();
    @re = query("select key, frase, type from fenite_rep");
    undef %resp;
    %resp = ();

    foreach my $tmp (@re) {
        my @t = split(/\|/, $tmp);
        $resp{$t[0]} = "$t[1]|$t[2]";
    }
}

_load();

# Monitor messages queue
threads->create(\&sendToChat)->detach();

# Monitor all message queue
threads->create(\&_loop)->detach();

# sleep(0.3);

my $lastupdate = 0;
while(1) {
    my $msg = $bot->start($lastupdate);
    $lastupdate = $msg->{update_id};
    #print($lastupdate);
    #$bot->_log(Dumper($msg));
    push(@all, $msg);
}

sub _loop {
    while(1) {
        if(@all > 0) {
            my $m = shift(@all);
            threads->create(\&_process, $m)->detach();
        }
        sleep(0.3);
    }
}

sub _process {
    my $msg = shift;
	my $u = $msg->{from}{username};
    if(!$u) {
        $u = $msg->{from}{first_name};
    }
    
    my $text = $msg->{text};
    $text = $msg->{caption} if($msg->{caption});

    if($msg->{voice}) {
        my $file_id = $msg->{voice}{file_id};

        my $u = "https://api.telegram.org/bot$bot->{config}{token}/getFile?file_id=$file_id";
        my $r = get($u);
        my $json = JSON->new->utf8->decode($r);

        my $f = $json->{result}->{file_path};

        $u = "https://api.telegram.org/file/bot$bot->{config}{token}/$f";
        system("wget -q -O $file_id.ogg $u");

        my $speech = Google::Cloud::Speech->new(
            file    => "$file_id.ogg",
            encoding => 'ogg_opus',
            language => 'es-DO',
            secret_file => '/home/ec2-user/fenite/api.json'
        );

        my $operation = $speech->syncrecognize();

        $text = (split(/\"/,JSON->new->utf8->encode($operation->results)))[7];
        #$bot->_log($text);

        unlink("$file_id.ogg");
    }

    if($text =~ /$regex/i) {
        # Responder a los MMGS
        my $m = $mmgs[rand @mmgs];
        chomp($m);

        _send($msg, $m, "\@" . $u);

        my $nn = $u;
        $nn =~ s/\@|\s//g;
        mmg($msg->{chat}{id}, $nn);
        return;
    }

    # Responder a di lo tuyo
    if($text =~ /di lo tuyo|Say your thing/i) {
        my $fu = $msg->{reply_to_message}{from}{username} ? 
                   $msg->{reply_to_message}{from}{username} : 
                   $msg->{reply_to_message}{from}{first_name};

        $fu = $u if(!$fu || $fu eq "fenite_bot");
        $fu = $u if($u eq "ChargingStar");

        my $m = $mmgs[rand @mmgs];
        chomp($m);
        
        _send($msg, $m, "\@" . $fu);

        return;
    }

    # Reload
    if($text =~ /reload/i && $u =~ /$op/i) {
        _load();
        sendmsg($msg->{chat}{id}, "reload...");
        return;
    }

    # Commandos en plugins
    if($msg->{text} =~ /^\//) {
        $bot->process($msg);
	    return;
    }else{
        # Responder texto
        foreach my $key (keys %resp) {
            if($msg->{text} =~ /$key/i) {
                _send($msg, $resp{$key});
                last;
            }
        }
    }

}

sub _send {
    my $msg = shift;
    my $m = shift;
    my $codename = shift;

    my @t = split(/\|/, $m);
    if($t[1] eq "document") {
        $bot->sendDocument([
            chat_id => $msg->{chat}{id},
            document => $t[0],
            caption => $codename
        ]);
    }elsif($t[1] eq "photo") {
        $bot->sendPhoto([
            chat_id => $msg->{chat}{id},
            photo => $t[0],
            caption => $codename
        ]);
    }elsif($t[1] eq "voice") {
        $bot->sendVoice([
            chat_id => $msg->{chat}{id},
            voice => $t[0],
            caption => $codename
        ]);
    }elsif($t[1] eq "audio") {
        $bot->sendAudio([
            chat_id => $msg->{chat}{id},
            audio => $t[0],
            caption => $codename
        ]);
    }elsif($t[1] eq "video") {
        $bot->sendVideo([
            chat_id => $msg->{chat}{id},
            video => $t[0],
            caption => $codename
        ]);
    }elsif($t[1] eq "sticker") {
        if($codename) {
            $bot->sendMessage([
                chat_id => $msg->{chat}{id},
                text => $codename
            ]);
        }
        $bot->sendSticker([
            chat_id => $msg->{chat}{id},
            sticker => $t[0]
        ]);
    }else{
        $m = $codename . " " . $t[0];
        sendmsg($msg->{chat}{id}, $m);
    }
}

sub mmg {
    my $chatid = shift;
    my $codename = shift;

    my $year = strftime "%Y", localtime;

    # Select
    my $query = "select count(*) from fenite_mmg where codename = ? and chatid = ? and year = ?";
    my @param = ($codename, $chatid, $year);
    my @ret = query($query, @param);

    my $qry = "";

    if($ret[0] > 0) {
        # Update
        $qry = "update fenite_mmg set count = count + 1 where codename = ? and chatid = ? and year = ?";
    }else{
        # Insert
        $qry = "insert into fenite_mmg (codename, chatid, count, year) values (?,?,1,?)";
    }

    my @param_qry = ($codename, $chatid, $year);
    insert($qry, @param_qry);
}

