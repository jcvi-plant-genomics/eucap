package JCVI::DB::asm_feature;

use base 'JCVI::DB::CDBI';

__PACKAGE__->set_up_table('asm_feature');
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
