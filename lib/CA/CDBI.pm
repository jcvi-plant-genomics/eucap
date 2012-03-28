package CA::CDBI;
use warnings;
use strict;
use base 'Class::DBI::mysql';

my ($dsn, $username, $password) = getConfig();

__PACKAGE__->connection( $dsn, $username, $password );

sub getConfig {
  return ('dbi:mysql:MTGCommunityAnnot:mysql51-lan-pro','vkrishna', 'L0g!n2db');
}

1;
