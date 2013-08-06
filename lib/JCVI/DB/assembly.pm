package JCVI::DB::assembly;

use base 'JCVI::DB::CDBI';

__PACKAGE__->set_up_table('assembly');
__PACKAGE__->set_sql(get_seqlength => "SELECT datalength(sequence) FROM __TABLE__ WHERE %s = ?");

1;
