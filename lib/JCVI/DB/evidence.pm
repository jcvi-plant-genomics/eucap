package AnnotDB::DB::evidence;

use base 'AnnotDB::DB::CDBI';

__PACKAGE__->table('evidence');
__PACKAGE__->columns(All => qw/id feat_name ev_type accession end5 end3 rel_end5 rel_end3 m_lend m_rend curated date assignby change_log save_history method per_id per_sim score db pvalue domain_score expect_domain total_score expect_whole chainID/);
#__PACKAGE__->set_up_table('evidence');

1;
