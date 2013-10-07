package JCVI::DB::clone_info;

use base 'JCVI::DB::CDBI';

__PACKAGE__->set_up_table('clone_info');
__PACKAGE__->set_sql(
    get_clone_name => qq{
        SELECT c.clone_name FROM clone_info c, ident i, asm_feature a
        WHERE i.locus = ? AND a.feat_name = i.feat_name
        AND a.feat_type = "model" AND c.asmbl_id = a.asmbl_id
        AND c.is_public = 1
    }
);

1;
