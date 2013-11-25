package AnnotDB::DB::feat_link;

use base 'AnnotDB::DB::CDBI';

__PACKAGE__->set_up_table('feat_link');

__PACKAGE__->set_sql(
    get_children => qq{
        SELECT fl.child_feat
        FROM feat_link fl LEFT JOIN phys_ev p ON p.feat_name = fl.child_feat
        WHERE fl.parent_feat = ? AND p.feat_name = fl.child_feat
        AND p.ev_type = "working"
    }
);

1;
