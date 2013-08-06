package EuCAP::Apps::Blast;
use strict;
use File::Temp;

#Bioperl modules (SeqIO and SearchIO)
use Bio::SeqIO;
use Bio::SearchIO;

use base 'Exporter';
our (@ISA, @EXPORT);

@ISA    = qw(Exporter);
@EXPORT = qw(run_blast);

# Read the eucap.ini configuration file
my %cfg = ();
tie %cfg, 'Config::IniFiles', (-file => 'eucap.ini');

# Webserver path params
my $WEBSERVER_DOC_PATH = $cfg{'webserver'}{'docpath'};
my $WEBSERVER_TEMP_DIR = $WEBSERVER_DOC_PATH . '/tmp';

# Blast config vars
my $PROTEOME_BLAST_DB = $WEBSERVER_DOC_PATH . '/blast_dbs/' . $cfg{'blast'}{'blastdb'};
my $BLASTALL          = $cfg{'blast'}{'blastall'};
    
sub run_blast {
    my ($session, $cgi) = @_;

    my $body_tmpl   = HTML::Template->new(filename => "./tmpl/blast_results.tmpl");
    my $fasta_param = $cgi->param('fasta');
    my $seq_type    = $cgi->param('seqtype');
    my $evalue      = $cgi->param('evalue');

    ###### set up temp files##############
    my $blast_out_fh = File::Temp->new(
        TEMPLATE => 'tempXXXXXXXXX',
        DIR      => $WEBSERVER_TEMP_DIR,
        SUFFIX   => '.blast',
        UNLINK   => 1,
    ) or die;

    my $fasta_out_fh = File::Temp->new(
        TEMPLATE => 'tempXXXXXXXXX',
        DIR      => $WEBSERVER_TEMP_DIR,
        SUFFIX   => '.fasta',
        UNLINK   => 1,
    ) or die;

    print STDERR $fasta_out_fh->filename . "\n";
    print STDERR $blast_out_fh->filename . "\n";

    my $blast_program = $seq_type eq 'protein' ? 'blastp' : 'blastx';

    #need to do error checking if bad sequence passed
    my $string_fh = IO::String->new($fasta_param);
    my $seqio_in  = Bio::SeqIO->new(
        -fh     => $string_fh,
        -format => 'fasta',
    );
    my $seqio_out = Bio::SeqIO->new(
        -fh     => $fasta_out_fh,
        -format => 'fasta',
    );

    $seqio_out->write_seq($seqio_in->next_seq);

    system( "$BLASTALL -p $blast_program -d $PROTEOME_BLAST_DB -i "
          . $fasta_out_fh->filename
          . " -e $evalue  -v 20 -b 20 -o "
          . $blast_out_fh->filename);

    my $blast_parser = Bio::SearchIO->new(
        -format => 'blast',
        -file   => $blast_out_fh->filename
    );

    my $blast_results = {};

    my $result    = $blast_parser->next_result;
    my $hit_count = 0;
    $blast_results->{'total_hits'} = $result->num_hits;
    $blast_results->{'query_name'} = $result->query_name;
    while (my $hit = $result->next_hit) {
        $hit_count++;
        $blast_results->{hits}->{$hit_count} = {};

        my $description = $hit->description;
        $description =~
s/\s+chr\d{1}\s+\d+\-\d+\s+.*|\s+contig_\d+\s+\d+\-\d+\s+.*|\s+\w{2}\d+\.\d+\s+\d+\-\d+\s+.*//gs;

        $blast_results->{hits}->{$hit_count}->{hit_name}        = filter_hit_name($hit->name);
        $blast_results->{hits}->{$hit_count}->{hit_description} = $description;
        $blast_results->{hits}->{$hit_count}->{e_value}         = $hit->significance;
        $blast_results->{hits}->{$hit_count}->{score}           = $hit->raw_score;
        $blast_results->{hits}->{$hit_count}->{length}          = $hit->length;
    }

    #annotate($session, $cgi, 0, $blast_results);
    if ($blast_results) {
        $body_tmpl->param(
            blast_results => 1,
            total_hits    => $blast_results->{total_hits},
            query_name    => $blast_results->{query_name}
        );

        my $blast_loop = [];
        for my $hit (keys %{ $blast_results->{hits} }) {
            my $row = {};
            $row->{locus}       = $blast_results->{hits}->{$hit}->{hit_name};
            $row->{description} = $blast_results->{hits}->{$hit}->{hit_description};
            $row->{e_value}     = $blast_results->{hits}->{$hit}->{e_value};
            $row->{score}       = $blast_results->{hits}->{$hit}->{score};
            $row->{length}      = $blast_results->{hits}->{$hit}->{length};
            push(@$blast_loop, $row);
        }
        $body_tmpl->param(blast_loop => $blast_loop);
    }

    # HTTP HEADER
    print $session->header(-type => 'text/html');

    print $body_tmpl->output;
}

sub filter_hit_name {

    #this has to be changed based on the defline of your proteome file
    #returns just the locus name
    my ($hit_name) = @_;
    $hit_name =~ /^IMGA\|(\S+)\.\d+/;
    if ($1) {
        return $1;
    }
    else {
        return $hit_name;
    }
}

1;