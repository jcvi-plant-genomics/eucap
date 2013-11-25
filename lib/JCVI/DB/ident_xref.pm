package AnnotDB::DB::ident_xref;

use base 'AnnotDB::DB::CDBI';

__PACKAGE__->set_up_table('ident_xref');

__PACKAGE__->set_sql(
    get_gb_acc => qq{
        SELECT x.ident_val FROM ident_xref x, ident i
        WHERE i.locus LIKE ? AND i.pub_locus IS NOT NULL
        AND x.feat_name = i.feat_name
        AND x.xref_type = "genbank accession"
        ORDER BY x.mod_date DESC
    }
);

1;
