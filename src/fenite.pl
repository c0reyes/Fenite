#!/usr/bin/perl

use strict;
use threads;
use Telegram::Bot;
use HTTP::Daemon;
use Geo::Distance;
use POSIX qw(strftime);
use Encode qw(encode);
use Data::Dumper;

use forks;
use forks::shared deadlock => {detect=> 1, resolve => 1};

use lib '.';
use Fenite qw(query update insert);

my @send_messages;

my @mmgs = ();
my $op = "";
my @o = ();
my @mm = ();
my @r = ();
my $regex = "";

my %resp = ();

# Bot
my $bot = new Telegram::Bot;

share(@send_messages);

$SIG{CHLD} = 'IGNORE';

local $SIG{__WARN__} = sub {
    my $message = shift;
    print $message . "\n";
};

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
        sleep(1);
    }
}

sub _load {
    # MMGs 
    @mmgs = ();
    @mmgs = query("select frase, type from fenite_frases order by random()");

    # Operadores
    @o = ();
    @o = query("select codename from fenite_op");
    $op = join("|", @o);
    $op =~ s/\s\n|\n//g;

    # Regex
    @r = ();
    @r = query("select regex from fenite_regex");
    $regex = join("|", @r);
    $regex =~ s/\s\n|\n//g;

    # Resp
    my @re = ();
    @re = query("select key, frase, type from fenite_rep");
    %resp = ();

    foreach my $tmp (@re) {
        my @t = split(/\|/, $tmp);
        $resp{$t[0]} = "$t[1]|$t[2]";
    }
}

_load();

# Monitor messages queue
threads->create(\&sendToChat)->detach();

# sleep(0.3);

while (my $msg = $bot->start) {
    #$bot->_log(Dumper($msg));
	my $u = $msg->{from}{username};
    if(!$u) {
        $u = $msg->{from}{first_name};
    }
    
    if($msg->{text} =~ /$regex/i) {
        # Responder a los MMGS
        my $m = $mmgs[rand @mmgs];
        chomp($m);

        _send($msg, $m, "\@" . $u);

        my $nn = $u;
        $nn =~ s/\@|\s//g;
        mmg($msg->{chat}{id}, $nn);
        sleep(0.3);
        next;
    }elsif($msg->{text} !~ /^\//) {
        # Responder texto
        foreach my $key (keys %resp) {
            if($msg->{text} =~ /$key/i) {
                _send($msg, $resp{$key});
                last;
            }
        }
    }

    # Responder a di lo tuyo
    if($msg->{text} =~ /di lo tuyo|Say your thing/i) {
        my $fu = $msg->{reply_to_message}{from}{username} ? 
                   $msg->{reply_to_message}{from}{username} : 
                   $msg->{reply_to_message}{from}{first_name};

        $fu = $u if(!$fu || $fu eq "fenite_bot");

        my $m = $mmgs[rand @mmgs];
        chomp($m);
        
        _send($msg, $m, "\@" . $fu);

        next;
    }

    # Reload
    if($msg->{text} =~ /reload/i && $u =~ /$op/i) {
        _load();
        sendmsg($msg->{chat}{id}, "reload...");
        next;
    }

    # Commandos en plugins
    if($msg->{text} =~ /^\//) {
        $bot->process($msg);

        if($msg->{text} =~ /add|del/) {
            _load();
        }
        next;
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

    # Select
    my $query = "select count(*) from fenite_mmg where codename = ? and chatid = ?";
    my @param = ($codename, $chatid);
    my @ret = query($query, @param);

    my $qry = "";

    if($ret[0] > 0) {
        # Update
        $qry = "update fenite_mmg set count = count + 1 where codename = ? and chatid = ?";
    }else{
        # Insert
        $qry = "insert into fenite_mmg (codename, chatid, count) values (?,?,1)";
    }

    my @param_qry = ($codename, $chatid);
    insert($qry, @param_qry);
}

