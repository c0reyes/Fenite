package Reddit;

use Exporter qw(import);
use LWP::Simple;
use JSON;

our @EXPORT_OK = qw(reddit);

sub reddit {
    my ($self, $msg, $url) = @_;

    my $reddit = get($url);
    my $json = JSON->new->utf8->decode($reddit);

    my $children = $json->{data}->{children};
    my @data;

    for my $child (@$children) {
        if($child->{data}->{secure_media}->{reddit_video}->{fallback_url}) {
            my %c = ();
            $c{'url'} = $child->{data}->{secure_media}->{reddit_video}->{fallback_url};
            $c{'type'} = "video";
            push @data, \%c;
            next;
        }elsif($child->{data}->{url}) {
            my %c = ();
            $c{'url'} = $child->{data}->{url};
            $c{'type'} = "photo";
            push @data, \%c;
        }elsif($child->{data}->{url_overridden_by_dest}) {
            my %c = ();
            $c{'url'} = $child->{data}->{url_overridden_by_dest};
            $c{'type'} = "photo";
            push @data, \%c;
        }
    }

    my %send = %{$data[rand @data]};

    if($send{'type'} eq "photo") {
        $self->sendPhoto([
            chat_id => $msg->{chat}{id},
            photo => $send{'url'}
        ]);
    }elsif($send{'type'} eq "video") {
        $self->sendVideo([
            chat_id => $msg->{chat}{id},
            video => $send{'url'}
        ]);
    }
}


1;
