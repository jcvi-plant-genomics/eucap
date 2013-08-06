package JCVI::DB::ident;

use base 'JCVI::DB::CDBI';

__PACKAGE__->set_up_table('ident');
__PACKAGE__->set_sql(get_loci => qq{
        SELECT i.feat_name, i.locus, i.com_name FROM ident i, clone_info c, asm_feature a
        WHERE i.locus LIKE ? AND a.feat_name = i.feat_name AND a.feat_type = "TU" AND 
        c.asmbl_id = a.asmbl_id AND c.is_public = 1   
    }
);

1;