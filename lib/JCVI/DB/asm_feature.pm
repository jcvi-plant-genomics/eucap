package AnnotDB::DB::asm_feature;

use base 'AnnotDB::DB::CDBI';

__PACKAGE__->table('asm_feature');
__PACKAGE__->columns(All => qw/feat_id feat_type feat_class feat_method end5 end3 comment assignby date sequence protein feat_name lock_id asmbl_id parent_id change_log save_history is_gb db_xref pub_comment curated sequence_datalength protein_datalength/);
#__PACKAGE__->set_up_table('asm_feature');

__PACKAGE__->set_sql(
    get_exons => qq{
        SELECT a.feat_name, a.end5, a.end3
        FROM asm_feature a, phys_ev p, feat_link fl
        WHERE fl.parent_feat = ? AND a.feat_name = fl.child_feat
        AND a.feat_type = "exon" AND p.feat_name = a.feat_name
        AND p.ev_type = "working"
    }
);
__PACKAGE__->set_sql(
    get_cds => qq{
        SELECT a.feat_name, a.end5, a.end3
        FROM asm_feature a, phys_ev p, feat_link fl
        WHERE fl.parent_feat = ? AND a.feat_name = fl.child_feat
        AND a.feat_type = "CDS" AND p.feat_name = a.feat_name
        AND p.ev_type = "working"
    }
);

1;
