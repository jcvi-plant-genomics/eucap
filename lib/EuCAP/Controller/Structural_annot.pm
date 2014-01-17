package EuCAP::Controller::Structural_annot;

use strict;
use EuCAP::DBHelper;
use AnnotDB::DBHelper;

use Bio::SeqFeature::Generic;
use Bio::Graphics;
use Bio::Graphics::Feature;

use Data::Dumper;

use base 'Exporter';
our (@ISA, @EXPORT);

@ISA    = qw(Exporter);
@EXPORT = qw(structural_annotation submit_structural_annotation);

# Read the eucap.ini configuration file
my %cfg = ();
tie %cfg, 'Config::IniFiles', (-file => 'eucap.ini');

# Webserver path params
my $APACHE_DOC_ROOT    = $cfg{'webserver'}{'htdocs'};
my $WEBSERVER_TEMP_REL = $cfg{'webserver'}{'tmprel'};

sub structural_annotation {
    my ($session, $cgi) = @_;

    my $locus_id = $cgi->param('locus_id');
    my $anno_ref = $session->param('anno_ref');

    # HTTP HEADER
    print $session->header(-type => 'text/plain');

    my $locus_obj   = selectrow({ table => 'loci', where => { locus_id => $locus_id } });
    my $gene_locus  = $locus_obj->gene_locus;
    my $gene_symbol = $locus_obj->gene_symbol;

    my $ca_model_json = $cgi->param('model_json');
    my $body_tmpl = HTML::Template->new(filename => "./tmpl/structural_annotation.tmpl");

    my ($gff_locus_obj, $gene_models) = ($gene_locus ne "") ? get_annotation_db_features({locus => $gene_locus}) : undef;

    #when hooked into script - look for saved JSON in table if none passed as param
    #if no model JSON passed to script, create new from annotation gene model
    my ($ca_model_ds, $sa_object);
    if (!$ca_model_json) {    #JSON not passed as a parameter
        $sa_object = selectrow(
            {
                table => 'structural_annot_edits',
                where => { locus_id => $locus_id, user_id => $anno_ref->{user_id} }
            }
        );
        $sa_object = selectrow({ table => 'structural_annot', where => { locus_id => $locus_id } })
          if (not defined $sa_object);

        #print STDERR Dumper($sa_object);
        $ca_model_json = $sa_object->model if $sa_object;
    }
    if (!$ca_model_json) {    #no model JSON as a parameter or in the db
        ($ca_model_ds, $ca_model_json) = generate_initial_ca_model_ds($gene_models->[0]);
    }
    else {
        my $json_handler = JSON->new;
        $ca_model_ds = $json_handler->decode($ca_model_json);
    }
    my $ca_model_feature = create_ca_model_feature($ca_model_ds);
    my ($url, $map, $map_name) = create_ca_image_and_map(
        {
            locus_obj        => $gff_locus_obj,
            gene_models      => $gene_models,
            ca_model_feature => $ca_model_feature
        }
    );
    $map = add_js_event_to_map($map, $gene_models->[0]) if($gene_models->[0]);
    my $ca_anno_loop = generate_table($ca_model_ds);

    $body_tmpl->param(
        img_path     => $url,
        map_name     => $map_name,
        map          => $map,
        ca_anno_loop => $ca_anno_loop,
        locus_id     => $locus_id,
        gene_locus   => $gene_locus,
        locus_type   => $ca_model_ds->{type},
        locus_seq_id => $ca_model_ds->{seq_id},
        locus_start  => $ca_model_ds->{start},
        locus_stop   => $ca_model_ds->{stop},
        locus_strand => $ca_model_ds->{strand},

        #model_json   => $ca_model_json,
    );

    print $body_tmpl->output;
}

sub submit_structural_annotation {
    my ($session, $cgi) = @_;
    my $gene_locus = $cgi->param('gene_locus');
    my $anno_ref   = $session->param('anno_ref');

    my $save_edits    = {};
    my $locus_obj     = selectrow({ table => 'loci', where => { gene_locus => $gene_locus } });
    my $locus_id      = $locus_obj->locus_id;
    my $ca_model_json = $cgi->param('model_json');

    #HTTP HEADER
    print $session->header(-type => 'text/plain');

    my $struct_annot_hashref = {};

    $struct_annot_hashref = selectrow_hashref(
        {
            table => 'structural_annot_edits',
            where => { locus_id => $locus_id, user_id => $anno_ref->{user_id} }
        }
    );
    my $sa_id = $struct_annot_hashref->{sa_id};
    if (scalar keys %{$struct_annot_hashref} == 0) {
        $struct_annot_hashref =
          selectrow_hashref({ table => 'structural_annot', where => { locus_id => $locus_id } });
    }

    my $struct_annot_edits_hashref =
      cgi_to_hashref({ cgi => $cgi, table => 'structural_annot', id => undef });

    ($struct_annot_edits_hashref, $save_edits->{structural_annot}) = cmp_db_hashref(
        {
            orig     => $struct_annot_hashref,
            edits    => $struct_annot_edits_hashref,
            is_admin => $anno_ref->{is_admin}
        }
    );

    if (defined $save_edits->{structural_annot}) {
        my $struct_annot_edits_obj = selectrow(
            {
                table => 'structural_annot_edits',
                where => { locus_id => $locus_id, user_id => $anno_ref->{user_id} }
            }
        );
        if (defined $struct_annot_edits_obj) {
            $struct_annot_edits_obj->model($ca_model_json);
            $struct_annot_edits_obj->update;
        }
        else {
            $struct_annot_edits_obj = do(
                'insert',
                'structural_annot_edits',
                {
                    sa_id    => $sa_id,
                    user_id  => $anno_ref->{user_id},
                    locus_id => $locus_id,
                    model    => $ca_model_json,
                }
            );
            $struct_annot_edits_obj->update;
        }
        print "Structure edits saved!";
    }
    else {
        print "No changes to save!";
    }

    $anno_ref->{loci}->{$locus_id}->{has_structural_annot} = 1;
    $session->param('anno_ref', $anno_ref);
    $session->flush;
}

############## Structural Annotation Subroutines #####################
sub generate_initial_ca_model_ds {
    my ($ref_gene_model) = @_;
    my @subfeatures = $ref_gene_model->get_SeqFeatures();
    @subfeatures =
      sort { $ref_gene_model->strand == 1 ? $a->start <=> $b->start : $b->start <=> $a->start }
      @subfeatures;
    my $comm_anno_ds = {};
    $comm_anno_ds->{subfeatures} = [];
    $comm_anno_ds->{type}        = $ref_gene_model->primary_tag;
    $comm_anno_ds->{seq_id}      = $ref_gene_model->seq_id;
    $comm_anno_ds->{start}       = $ref_gene_model->start;
    $comm_anno_ds->{stop}        = $ref_gene_model->stop;
    $comm_anno_ds->{strand}      = $ref_gene_model->strand;

    for my $subfeature (@subfeatures) {
        my $subfeature_ds = {};
        $subfeature_ds->{type}  = $subfeature->primary_tag;
        $subfeature_ds->{start} = $subfeature->start;
        $subfeature_ds->{stop}  = $subfeature->stop;
        push(@{ $comm_anno_ds->{subfeatures} }, $subfeature_ds);
    }
    my $json_handler         = JSON->new;
    my $comm_anno_model_json = $json_handler->encode($comm_anno_ds);
    return ($comm_anno_ds, $comm_anno_model_json);

}

sub Bio::Graphics::Panel::create_web_map {
    my $self = shift;
    my ($name, $linkrule, $titlerule, $targetrule) = @_;
    $name ||= 'map';
    my $boxes = $self->boxes;
    my (%track2link, %track2title, %track2target);

    my $map = qq(<map name="$name" id="$name">\n);
    foreach (@$boxes) {
        my ($feature, $left, $top, $right, $bottom, $track) = @$_;
        next unless $feature->can('primary_tag');
        my $primary_tag = $feature->primary_tag;
        next
          unless (($primary_tag)
            and (($primary_tag =~ /utr/i) or ($primary_tag =~ /cds/i)));

        my $lr = $track2link{$track} ||= (
            defined $track->option('link')
            ? $track->option('link')
            : $linkrule
        );
        next unless $lr;

        my $tr =
          exists $track2title{$track} ? $track2title{$track}
          : $track2title{$track} ||= (
            defined $track->option('title') ? $track->option('title')
            : $titlerule
          );
        my $tgr =
          exists $track2target{$track} ? $track2target{$track}
          : $track2target{$track} ||= (
            defined $track->option('target') ? $track->option('target')
            : $targetrule
          );

        my $href   = $self->make_link($lr,  $feature);
        my $alt    = $self->make_link($tr,  $feature);
        my $target = $self->make_link($tgr, $feature);
        $alt = $self->make_title($feature) unless defined $alt;

        my $a = $alt    ? qq(title="$alt" alt="$alt") : '';
        my $t = $target ? qq(target="$target")        : '';
        my $h = $href   ? qq(href="$href")            : '';

        $map .= qq(<area shape="rect" coords="$left,$top,$right,$bottom" $h $a $t/>\n);
    }
    $map .= "</map>\n";
    $map;
}

sub add_js_event_to_map {
    my ($map, $model_feature) = @_;
    my $end5 = $model_feature->strand == 1 ? $model_feature->start : $model_feature->end;
    my $new_map;
    my $string_io = IO::String->new($map);
    while (<$string_io>) {
        my $line = $_;
        if ($line =~ /^<area/) {

            #start = end5 - $stop = end3
            my ($start, $stop) = $line =~ /href="(\d+)-(\d+)"/;
            my $rel_end5 = $start - $end5 + 1;
            my $rel_end3 = $stop - $end5 + 1;
            $line =~
s/href="\d+-\d+"/onmouseover="displayCoords($start, $stop, $rel_end5, $rel_end3);setCursor();" onmouseout="restoreCursor()"/;
        }
        $new_map .= $line;
    }

    return $new_map;
}

sub generate_table {
    my ($comm_anno_ds) = @_;
    my $comm_anno_table = [];
    for my $subfeature (@{ $comm_anno_ds->{subfeatures} }) {
        my $row = {};
        $row->{CDS}   = $subfeature->{type} eq 'CDS' ? 1 : 0;
        $row->{start} = $subfeature->{start};
        $row->{stop}  = $subfeature->{stop};
        push(@{$comm_anno_table}, $row);
    }
    return $comm_anno_table;
}

sub create_ca_model_feature {
    my ($ca_model_ds)         = @_;
    my $ca_model_subfeat_objs = [];
    my $seq_id                = $ca_model_ds->{seq_id};
    my $strand                = $ca_model_ds->{strand};
    for my $subfeature (@{ $ca_model_ds->{subfeatures} }) {
        my $subfeat_obj = Bio::Graphics::Feature->new(
            -seq_id => $seq_id,
            -start  => $subfeature->{start},
            -stop   => $subfeature->{stop},
            -type   => $subfeature->{type},
            -strand => $strand,    #strand is flipped by *-1, if strand is 0, it doesn't work

        );
        push(@$ca_model_subfeat_objs, $subfeat_obj);
    }
    my $ca_model_feature = Bio::Graphics::Feature->new(
        -segments => $ca_model_subfeat_objs,
        -type     => 'mRNA',
        -strand   => $strand,
        -name     => $ca_model_ds->{name},
        -seq_id   => $seq_id,

    );

    return $ca_model_feature;
}

sub create_ca_image_and_map {
    my ($arg_ref) = @_;

    my ($end5,   $end3, $strand, $length);
    my ($c_end5, $c_end3) = get_ends_from_feature($arg_ref->{ca_model_feature});
    if(defined $arg_ref->{locus_obj}) {
        my ($l_end5, $l_end3) = get_ends_from_feature($arg_ref->{locus_obj});
        if ($arg_ref->{locus_obj}->strand == 1) {
            $end5 = $c_end5 < $l_end5 ? $c_end5 : $l_end5;
            $end3 = $c_end3 > $l_end3 ? $c_end3 : $l_end3;
        }
        else {
            $end3 = $c_end5 > $l_end5 ? $c_end5 : $l_end5;
            $end5 = $c_end3 < $l_end3 ? $c_end3 : $l_end3;
        }
        $strand = $arg_ref->{locus_obj}->strand;
        $length = $arg_ref->{locus_obj}->length;
    }
    else {
          ($end5, $end3) =
            ($arg_ref->{ca_model_feature}->strand == 1) ? ($c_end5, $c_end3) : ($c_end3, $c_end5);
        $strand = $arg_ref->{ca_model_feature}->strand;
        $length = $arg_ref->{ca_model_feature}->length;
    }

#flip will have to be dynamically controlled by the strand of the ca  model or the primary working model

    my $panel = Bio::Graphics::Panel->new(
        -length     => $length,
        -key_style  => 'between',
        -width      => 600,
        -pad_left   => 20,
        -pad_right  => 20,
        -pad_top    => 20,
        -pad_bottom => 20,
        -start      => $end5,
        -end        => $end3,
        -flip       => ($strand == -1) ? 1 : 0,
    );

    $panel->add_track(
        arrow => Bio::SeqFeature::Generic->new(
            -start => $end5,
            -end   => $end3
        ),
        -bump   => 0,
        -double => 1,
        -tick   => 2,
        -key    => 'Abs Coords'
    );

    $panel->add_track(
        arrow => Bio::SeqFeature::Generic->new(
            -start  => $end5,
            -end    => $end3,
            -strand => $strand,
        ),
        -bump            => 0,
        -double          => 1,
        -tick            => 2,
        -relative_coords => 1,

        -key => 'Rel Coords'
    );

    $panel->add_track(
        $arg_ref->{locus_obj},
        -glyph       => 'box',
        -height      => 8,
        -description => 1,
        -label       => sub {
            my $feature = shift;
            my $note    = $feature->display_name();
            return $note;
        },
        -font2color => 'black',
        -bgcolor    => sub {
            my $feature = shift;
            my $note    = $feature->notes;
            if ($note =~ /^hypothetical/) {
                return "red";
            }
            elsif ($note =~ /^conserved hypothetical/) {
                return "blue";
            }
            elsif ($note =~ /^(expressed|unknown)/) {
                return "yellow";
            }
            elsif ($note =~ /transpos/) {
                return "black";
            }
            else {
                return "green";
            }
        },
        -fgcolor => 'black',
        -key     => 'Gene Loci'
    );

    $panel->add_track(
        $arg_ref->{gene_models},
        -glyph     => 'gene',
        -connector => 'solid',
        -label     => sub {
            my $feature = shift;
            my $note    = $feature->display_name();
            return $note;
        },
        -height       => 10,
        -key          => 'Gene Models',
        -utr_color    => 'white',
        -thin_utr     => 0,
        -fgcolor      => 'slateblue',
        -bgcolor      => 'skyblue',
        -box_subparts => 1,
    );

    $panel->add_track(
        $arg_ref->{ca_model_feature},
        -glyph        => 'gene',
        -connector    => 'solid',
        -label     => sub {
            my $feature = shift;
            my $note    = $feature->display_name();
            return $note;
        },
        -description  => 0,
        -fgcolor      => "#0A910D",
        -bgcolor      => "lightgreen",
        -utr_color    => "white",
        -height       => 10,
        -font2color   => "black",
        -box_subparts => 1,
        -key          => 'Community Annotation',
    );

    my ($url, $map, $map_name) = $panel->image_and_map(
        -root    => $APACHE_DOC_ROOT,
        -url     => $WEBSERVER_TEMP_REL,
        -link    => '$start-$end',
        -mapname => 'eucap_map',

    );
    $panel->finished;
    return ($url, $map, $map_name);
}

1;
