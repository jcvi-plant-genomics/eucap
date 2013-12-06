package EuCAP::DB::CDBI;

use warnings;
use strict;
use Config::IniFiles;
use base 'Class::DBI::mysql';
use Class::DBI::AbstractSearch;

my ($dsn, $username, $password) = getConfig();

__PACKAGE__->connection($dsn, $username, $password);

sub getConfig {
    my ($username, $password, $dbhost);

    # Read the eucap.ini configuration file
    my %cfg = ();
    tie %cfg, 'Config::IniFiles', (-file => 'eucap.ini');

    my $WEBTIER = ($ENV{'WEBTIER'} eq 'dev') ? 'dev' : 'prod';
    #local community annotation DB connection params
    my $CA_DB_NAME = $cfg{'eucap'}{'database'};
    my $CA_SERVER  = 'eucap-' . $WEBTIER;
    my ($CA_DB_USERNAME, $CA_DB_PASSWORD, $CA_DB_HOST) =
      ($cfg{$CA_SERVER}{'username'}, $cfg{$CA_SERVER}{'password'}, $cfg{$CA_SERVER}{'hostname'});
    my $CA_DB_DSN = join(':', ('dbi:mysql', $CA_DB_NAME, $CA_DB_HOST));

    return ($CA_DB_DSN, $CA_DB_USERNAME, $CA_DB_PASSWORD);
}

1;
