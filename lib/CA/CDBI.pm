package CA::CDBI;
use warnings;
use strict;
use Switch;
use base 'Class::DBI::mysql';

my ($dsn, $username, $password) = getConfig();

__PACKAGE__->connection($dsn, $username, $password);

sub getConfig {
    my ($username, $password, $dbhost);
    switch ($ENV{'WEBTIER'}) {
        case /dev/ { ($username, $password, $dbhost) = ('vkrishna', 'L0g!n2db', 'mysql-lan-pro'); }
        else { ($username, $password, $dbhost) = ('eucap', 'Zs5Nud6mDuhEVzKC', 'mysql-dmz-pro'); }
    }
    my $dbname = "MTGCommunityAnnot";
    my $dsn    = "dbi:mysql:$dbname:$dbhost";

    return ($dsn, $username, $password);
}

1;
