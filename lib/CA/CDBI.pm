package CA::CDBI;
# $Id: CDBI.pm 538 2007-07-24 00:19:51Z hamilton $
use warnings;
use strict;
use base 'Class::DBI::mysql';

my $database = 'community_annotation';
my $host = 'hamilton-lx';
my $user = 'access';
my $password = 'access';

__PACKAGE__->connection( "dbi:mysql:$database:$host", $user , $password );

1;
