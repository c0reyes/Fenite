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

	my $username = $msg->{from}{username};
    my $firstname = $msg->{from}{first_name};
    my $id = $msg->{from}{id};
    my $tme = "[" . encode("utf8", $firstname) . "](tg://user?id=" . $id. ")";

    my $username_reply;
    my $firstname_reply;
    my $id_reply;
    my $tme_reply;

    if($msg->{reply_to_message}) {
        $username_reply = $msg->{reply_to_message}{from}{username};
        $firstname_reply = $msg->{reply_to_message}{from}{first_name};
        $id_reply = $msg->{reply_to_message}{from}{id};
        $tme_reply = "[" . encode("utf8", $firstname_reply) . "](tg://user?id=" . $id_reply. ")";
    }
    
    my $text = $msg->{text};
    $text .= $msg->{caption};
    $text .= $msg->{reply_to_message}{text} if $text !~ /^\//;
    $text .= $msg->{reply_to_message}{caption} if $text !~ /^\//;

    # Voice to Text
    if($msg->{voice} || ($msg->{reply_to_message}{voice} && $text !~ /^\//)) {
        my $file_id = $msg->{voice}{file_id} || $msg->{reply_to_message}{voice}{file_id};

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

        $text .= (split(/\"/,JSON->new->utf8->encode($operation->results)))[7];

        unlink("$file_id.ogg");
    }

    # Read photo from LaTumba
    if(($msg->{photo} || ($msg->{reply_to_message}{photo} && $text !~ /^\//)) && $msg->{chat}{id} eq "-1001071751643") {
        my $file_id = $msg->{photo}{file_id} || $msg->{reply_to_message}{photo}{file_id};

        my $u = "https://api.telegram.org/bot$bot->{config}{token}/getFile?file_id=$file_id";
        my $r = get($u);
        my $json = JSON->new->utf8->decode($r);

        my $f = $json->{result}->{file_path};

        $u = "https://api.telegram.org/file/bot$bot->{config}{token}/$f";
        system("wget -q -O $file_id.jpg $u");
        $text .= qx/tesseract $file_id.jpg -/;
        unlink("$file_id.jpg");
    } 

    # Responder a los MMGS
    if($text =~ /$regex/i) {
        my $m = $mmgs[rand @mmgs];
        chomp($m);

        _send($msg, $m, $tme);

        $username =~ s/\@|\s//g;
        mmg($msg->{chat}{id}, $username, $id, $firstname, $msg->{chat}{title});
        return;
    }

    # Responder a di lo tuyo
    if($text =~ /di lo tuyo|Say your thing/i) {
        my $m = $mmgs[rand @mmgs];
        chomp($m);
        
        if((!$firstname_reply && !$username_reply) || $username_reply eq "fenite_bot") {
            _send($msg, $m, $tme);
        }else{
            _send($msg, $m, $tme_reply);
        }

        return;
    }

    # Reload
    if($text =~ /reload/i && $username =~ /$op/i) {
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
            if($msg->{text} =~ /$key[\s\n\r?!\.]|$key$/i) {
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
            caption => $codename,
            parse_mode => 'Markdown'
        ]);
    }elsif($t[1] eq "photo") {
        $bot->sendPhoto([
            chat_id => $msg->{chat}{id},
            photo => $t[0],
            caption => $codename,
            parse_mode => 'Markdown'
        ]);
    }elsif($t[1] eq "voice") {
        $bot->sendVoice([
            chat_id => $msg->{chat}{id},
            voice => $t[0],
            caption => $codename,
            parse_mode => 'Markdown'
        ]);
    }elsif($t[1] eq "audio") {
        $bot->sendAudio([
            chat_id => $msg->{chat}{id},
            audio => $t[0],
            caption => $codename,
            parse_mode => 'Markdown'
        ]);
    }elsif($t[1] eq "video") {
        $bot->sendVideo([
            chat_id => $msg->{chat}{id},
            video => $t[0],
            caption => $codename,
            parse_mode => 'Markdown'
        ]);
    }elsif($t[1] eq "animation") {
        $bot->sendVideo([
            chat_id => $msg->{chat}{id},
            animation => $t[0],
            caption => $codename,
            parse_mode => 'Markdown'
        ]);
    }elsif($t[1] eq "sticker") {
        if($codename) {
            $bot->sendMessage([
                chat_id => $msg->{chat}{id},
                text => $codename,
                parse_mode => 'Markdown'
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
    my $id = shift;
    my $firstname = shift;
    my $chat = shift;

    $codename = "*NA*" if(!$codename);
    $chat = "private" if(!$chat);

    my $year = strftime "%Y", localtime;

    # Select
    my $query = "select count(*) from fenite_mmg where id = ? and chatid = ? and year = ?";
    my @param = ($id, $chatid, $year);
    my @ret = query($query, @param);

    my $qry = "";
    my @param_qry = ();

    if($ret[0] > 0) {
        # UPDATE CON ID
        $qry = "update fenite_mmg set count = count + 1, codename = ?, firstname = ?, chat = ? where id = ? and chatid = ? and year = ?";
        @param_qry = ($codename, $firstname, $chat, $id, $chatid, $year);
    }else{
        @param = ();
        @ret = ();

        $query = "select count(*) from fenite_mmg where codename = ? and chatid = ? and year = ?";
        @param = ($codename, $chatid, $year);
        @ret = query($query, @param);

        if($ret[0] > 0) {
            # Update
            $qry = "update fenite_mmg set count = count + 1, id = ?, firstname = ?, chat = ? where codename = ? and chatid = ? and year = ?";
            @param_qry = ($id, $firstname, $chat, $codename, $chatid, $year);
        }else{
            # Insert
            $qry = "insert into fenite_mmg (codename, chatid, count, year, id, firstname, chat) values (?,?,1,?,?,?,?)";
            @param_qry = ($codename, $chatid, $year, $id, $firstname, $chat);
        }
    }

    insert($qry, @param_qry);
}

