package AnnotDB::DB::ident;

use base 'AnnotDB::DB::CDBI';

__PACKAGE__->table('ident');
__PACKAGE__->columns(All => qw/feat_name alt_locus date nt_com_name assignby pub_comment ec# pub_locus com_name species nt_comment is_pseudogene locus gene_sym auto_comment save_history comment/);
#__PACKAGE__->set_up_table('ident');

__PACKAGE__->set_sql(
    get_loci => qq{
        SELECT i.feat_name, i.locus, i.com_name
        FROM ident i, clone_info c, asm_feature a
        WHERE i.locus LIKE ? AND a.feat_name = i.feat_name
        AND a.feat_type = "TU" AND c.asmbl_id = a.asmbl_id
        AND c.is_public = 1
    }
);

__PACKAGE__->set_sql(
    get_models => qq{
        SELECT m.feat_name, m.locus
        FROM ident i, ident m, feat_link fl, asm_feature a, phys_ev p
        WHERE i.locus = ? AND fl.parent_feat = i.feat_name
        AND a.feat_name = fl.child_feat AND a.feat_type = "model"
        AND m.feat_name = a.feat_name AND p.feat_name = m.feat_name
        AND p.ev_type = "working"
    }
);

1;
