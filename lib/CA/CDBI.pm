package CA::CDBI;
# $Id: CDBI.pm 538 2007-07-24 00:19:51Z hamilton $
use warnings;
use strict;
use base 'Class::DBI::mysql';

my ($dsn, $username, $password) = getConfig();

__PACKAGE__->connection( $dsn, $username, $password );

sub getConfig {
  return ('dbi:mysql:MTGCommunityAnnot:mysql-lan-pro','vkrishna', 'L0g!n2db');
}

1;
