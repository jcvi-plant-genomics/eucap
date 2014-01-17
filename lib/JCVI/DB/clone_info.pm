package AnnotDB::DB::clone_info;

use base 'AnnotDB::DB::CDBI';

__PACKAGE__->table('clone_info');
__PACKAGE__->columns(All => qw/asmbl_id clone_id clone_name seq_group orig_annotation tigr_annotation status length final_asmbl fa_left fa_right fa_orient gb_acc gb_desc gb_comment gb_date comment assignby date lib_id seq_asmbl_id chromo date_for_release date_released authors1 authors2 seq_db is_public gb_keywords sequencing_type prelim license gb_gi gb_phase/);
#__PACKAGE__->set_up_table('clone_info');

__PACKAGE__->set_sql(
    get_clone_name => qq{
        SELECT c.clone_name FROM clone_info c, ident i, asm_feature a
        WHERE i.locus = ? AND a.feat_name = i.feat_name
        AND a.feat_type = "TU" AND c.asmbl_id = a.asmbl_id
        AND c.is_public = 1
    }
);

1;
