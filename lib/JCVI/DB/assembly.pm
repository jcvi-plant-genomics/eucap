package AnnotDB::DB::assembly;

use base 'AnnotDB::DB::CDBI';

__PACKAGE__->table('assembly');
__PACKAGE__->columns(All => qw/asmbl_id seq_id bac_id com_name type method ed_status redundancy perc_N seq# full_cds cds_start cds_end ed_pn ed_date comment sequence frameshift release_date lock_id lsequence quality ca_contig_id mod_date is_circular mod_pn sequence_datalength/);
 #__PACKAGE__->set_up_table('assembly');

__PACKAGE__->set_sql(get_seqlength => "SELECT datalength(sequence) FROM __TABLE__ WHERE %s = ?");

1;
