package Fenite;

use Exporter qw(import);
our @EXPORT_OK = qw(query insert update);

use DBI;

# DB
my $driver = "SQLite";
my $database = "fenite_database.db";
my $dsn = "DBI:$driver:dbname=$database";
my $userid = "";
my $password = "";

sub query {
    my $query = shift;
    my @param = @_;

    my @ret = ();

    my $dbh = DBI->connect($dsn, $userid, $password, { RaiseError => 1 })
        or die $DBI::errstr;
    
    my $sth = $dbh->prepare($query);
    for(my $i = 0; $i < @param; $i++) {
    	$sth->bind_param($i+1,$param[$i]);
	}
    $sth->execute() or die $DBI::errstr;
    
    while(my @row = $sth->fetchrow_array()) {
    	push(@ret, join("|", @row));
    }

    $dbh->disconnect();

    return @ret;
}

sub insert {
    my $query = shift;
    my @param = @_;

    my $dbh = DBI->connect($dsn, $userid, $password, { RaiseError => 1 })
        or die $DBI::errstr;
    
    my $sth = $dbh->prepare($query);
    for(my $i = 0; $i < @param; $i++) {
    	$sth->bind_param($i+1,$param[$i]);
	}
    $sth->execute() or die $DBI::errstr;
    
    $dbh->disconnect();
}

sub update {
	my $query = shift;
	my @param = @_;

	return insert($query, @param);
}

1;