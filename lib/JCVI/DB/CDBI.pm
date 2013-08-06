package JCVI::DB::CDBI;

use base 'Class::DBI::Sybase';
use strict;
use warnings;
use IO::File;

my ($dsn, $username, $password) = get_credentials();

#__PACKAGE__->set_db('mta1pseudos', $dsn, $username, $password);
__PACKAGE__->connection($dsn, $username, $password);
__PACKAGE__->set_sql(getdate => "SELECT getdate()");
__PACKAGE__->set_sql(set_textsize => "SET textsize ?");

sub get_credentials {
    return ("dbi:Sybase:server=SYBPROD;database=mta1pseudos", "vkrishna", "vkrishna9");
}

1;