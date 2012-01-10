#!/usr/local/bin/perl
# $Id: ca_pic_generator.pl 542 2007-07-24 18:25:31Z hamilton $
# EuCAP - Eukaryotic Community Annotation Package - 2007
# This script generates the pictures of the community annotation gene models for the website
# only pictures for loci with has_structural_annotation = 1 will be generated

use strict;
use warnings;
use Bio::DB::GFF;
use Bio::Graphics;
use Bio::SeqFeature::Generic;
use DBI;

#local GFF DB connection params
my $GFF_DB_ADAPTOR = 'dbi::mysql'; #Bio DB GFF
my $GFF_DB_NAME = 'rice';
my $GFF_DB_HOST = 'mysql-dmz';
my $GFF_DB_DSN = join( ':', ('dbi:mysql', $GFF_DB_NAME, $GFF_DB_HOST ) );
my $GFF_DB_USERNAME = 'access';
my $GFF_DB_PASSWORD ='access';

#local community annotation DB connection params
my $CA_DB_NAME = 'community_annotation';
my $CA_DB_HOST = 'hamilton-lx';
my $CA_DB_DSN = join( ':', ('dbi:mysql', $CA_DB_NAME, $CA_DB_HOST ) );
my $CA_DB_USERNAME = 'access';
my $CA_DB_PASSWORD = 'access';


my ( $user_id, $family_id);
my $result = GetOptions ("user_id=i" => \$user_id,
                         "family_id=i"   => \$family_id,
                        );
unless ($user_id && $family_id ) {
    die "Usage: load_ca_db_from excel.pl --user_id --pfam_id\n";
}


my $dbh = DBI->connect($CA_DB_DSN, $CA_DB_USERNAME, $CA_DB_PASSWORD) or die;

my $processed_transcript_aggregator = Bio::DB::GFF::Aggregator->new(-method => "processed_transcript",
                                                                    -main_method  => "mRNA",
                                                                    -sub_parts    => ["three_prime_UTR","CDS","five_prime_UTR"]
                                                                   );
my $match_aggregator = Bio::DB::GFF::Aggregator->new(-method => "match",
                                                     -main_method  => "match",
                                                     -sub_parts    => ["HSP"]
                                                    );

my $db = Bio::DB::GFF->new(-dsn => $GFF_DB_DSN,
                           -aggregator => [ $processed_transcript_aggregator,$match_aggregator ],
                           -user => $GFF_DB_USERNAME,
                           -pass => $GFF_DB_PASSWORD
                          );

#get the gene family info
my $sth_gene_fam = $dbh->prepare("select locus, gene_name, locus_id from loci where user_id = $user_id and family_id = $family_id and has_structural_annotation = \"1\" order by locus_id") or die;
$sth_gene_fam->execute;
my $gene_fam_info = $sth_gene_fam->fetchall_arrayref;
$sth_gene_fam->finish;

for (@$gene_fam_info){
	if ($_->[0] =~ m/^LOC/){
		get_ca_pix($_->[0], $_->[1], $_->[2], $user_id, $family_id);
	}
	elsif ($_->[0] =~ m/^Chr/) {
		#handle the ca with no aligned locus here
		get_ca_pix_noloc($_->[0], $_->[1], $_->[2], $user_id, $family_id);
	}
	else {
		warn ("unexpected gene name found: ".$_->[0]."\n"); 
	}
}

$dbh->disconnect;



sub get_ca_pix {
	my ($gene, $gene_name, $locus_id, $user_id, $family_id) = @_;
	my ($chr) = $gene =~ /^LOC_Os(\d\d)g\d{5}/;
	$chr =~ s/^0//;
	$chr = "Chr".$chr;
	my $chr_seg = $db->segment($chr);
	my @gene = $db->get_feature_by_name(-class => "Gene", -name => $gene, -ref=> $chr);
	
	#start and stop vars determine the length of the segment, thus the scale in the width
	my $start = $gene[0]->start;
	my $stop = $gene[0]->stop;
	my @models = $chr_seg->features(-types => ["processed_transcript:TIGR_annot_DB"], -start => $start+10000, -stop => $stop-10000 );
        my @com_anno = $db->get_feature_by_name(-types => ["processed_transcript:comm_anno"], -class => "mRNA", -name => "commanno_$locus_id", -ref=> $chr );

	unless (@com_anno) {warn "No com anno ret for: $gene - $gene_name \n";return;}
	 
	for my $ca_obj (@com_anno){ 
		if ($start < $stop){
			if ($ca_obj->start < $ca_obj->stop){
				if ($ca_obj->start < $start){
					$start = $ca_obj->start;
				}
				if ($ca_obj->stop > $stop){
					$stop = $ca_obj->stop;
				}
			}
			else {
				if ($ca_obj->start > $stop){
					$stop = $ca_obj->start;
				}
				if ($ca_obj->stop < $start){
					$start = $ca_obj->stop;
				}
			}
		}
 		else { 
			if ($ca_obj->start > $ca_obj->stop){
				if ($ca_obj->start > $start){
					$start = $ca_obj->start;
				}
				if ($ca_obj->stop < $stop){
					$stop = $ca_obj->stop;
				}
			}
			else {
				if ($ca_obj->start < $stop){
					$stop = $ca_obj->start;
				}
				if ($ca_obj->stop > $start){
					$start = $ca_obj->stop;
				}
			}
 		}
	}


my ($rel_start, $rel_stop);
if ($start < $stop){
	$rel_start = $start;
	$rel_stop = $stop;
}
else {
	$rel_start = $stop;
	$rel_stop = $start;
}

my $full_length = Bio::SeqFeature::Generic->new(-start=>$rel_start,-end=>$rel_stop);

my $panel = Bio::Graphics::Panel->new(-width => 500, -key_style => 'between', -grid => 1, -pad_left => 20, -pad_right => 20, -pad_top => 20, -pad_bottom  => 20, -spacing => 10, -start=> $rel_start, -stop=>$rel_stop);
my $ruler = $panel->add_track($full_length, -glyph => "arrow", -tick => 2, -fgcolor => 'black', -double  => 1 , -key => $chr);
my $model_track = $panel->add_track(\@models, -glyph => "processed_transcript", -label => 1, -fgcolor => "slateblue", -bgcolor => "skyblue", -utr_color => "white", -height => 10 );

my $comm_anno_track = $panel->add_track(\@com_anno, -glyph => "processed_transcript", -label => sub {my $f = shift; return $f->notes;} , -description => 0, -fgcolor => "#0A910D", -bgcolor => "lightgreen", -utr_color => "white" , -height => 10, -font2color => "black" );

open(OUT, ">".$user_id."_".$family_id."_".$locus_id.".png") or die "$!\n";
print OUT $panel->png;
close(OUT);
}

sub get_ca_pix_noloc {
	my ($location, $gene_name, $locus_id, $user_id, $family_id) = @_;
	my ($chr) = $location =~ /^(Chr\d+):/;
	my $chr_seg = $db->segment($chr);
	my @com_anno = $db->get_feature_by_name(-types => ["processed_transcript:comm_anno"], -class => "mRNA", -name => "commanno_$locus_id", -ref=> $chr );
	unless (@com_anno) {warn "No com anno ret for: $location - $gene_name \n";return;}
	
	my $start = $com_anno[0]->start;
	my $stop = $com_anno[0]->stop;
	
	my ($rel_start, $rel_stop);
	if ($start < $stop){
		$rel_start = $start;
		$rel_stop = $stop;
	}
	else {
		$rel_start = $stop;
		$rel_stop = $start;
	}

	my $full_length = Bio::SeqFeature::Generic->new(-start=>$rel_start,-end=>$rel_stop);

	my $panel = Bio::Graphics::Panel->new(-width => 500, -key_style => 'between', -grid => 1, -pad_left => 20, -pad_right => 20, -pad_top => 20, -pad_bottom  => 20, -spacing => 10, -start=> $rel_start, -stop=>$rel_stop);
	my $ruler = $panel->add_track($full_length, -glyph => "arrow", -tick => 2, -fgcolor => 'black', -double  => 1 , -key => $chr);

	my $comm_anno_track = $panel->add_track(\@com_anno, -glyph => "processed_transcript", -label => sub {my $f = shift; return $f->notes;} , -description => 0, -fgcolor => "#0A910D", -bgcolor => "lightgreen", -utr_color => "white" , -height => 10, -font2color => "black" );

	open(OUT, ">".$user_id."_".$family_id."_".$locus_id.".png") or die "$!\n";
	print OUT $panel->png;
	close(OUT);
}
