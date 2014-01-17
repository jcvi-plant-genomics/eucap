package AnnotDB::DB::phys_ev;

use base 'AnnotDB::DB::CDBI';

__PACKAGE__->table('phys_ev');
__PACKAGE__->columns(All => qw/id feat_name ev_type assignby datestamp type score/);
#__PACKAGE__->set_up_table('phys_ev');

1;
