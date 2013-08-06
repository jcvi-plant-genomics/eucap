package Textpresso::Helper;

use strict;

# Textpresso (for Publication store)
use TextpressoLibrary;
use lib TEXTPRESSO_LIB;

# Code borrowed from Textpresso 'docfinder' script
# Import global constants for Textpresso Database
use TextpressoGeneralTasks;
use TextpressoDatabaseGlobals;

use base 'Exporter';
our (@ISA, @EXPORT);

@ISA    = qw(Exporter);
@EXPORT = qw(get_pmids retrieve_pmid_record);

use constant QUERY_URI =>
  'http://www.ncbi.nlm.nih.gov/entrez/query.fcgi?cmd=Retrieve&db=pubmed&dopt=Abstract&list_uids=';

sub get_pmids {
    my ($arg_ref) = @_;

    my $response = {};

    # HTTP HEADER
    print $arg_ref->{cgi}->header(-type => 'application/json');

    my @query_output  = ();
    my $search_string = $arg_ref->{pmid};
    $search_string =~ s/^\s+|\s+$//gs;

    foreach my $lit (keys %{ (DB_LITERATURE) }) {
        my $dir = DB_ROOT . '/' . (DB_LITERATURE)->{$lit} . '/' . DB_TEXT . '/' . 'title/';
        my @files = <$dir/*$search_string*>;

        foreach my $file (@files) {
            my $id = $file;
            $id =~ s/$dir\///gs;

            my $title = `cat $file`;
            chomp $title;
            $title = InverseReplaceSpecChar($title);
            $title =~ s/\\//gs;
            $title =~ s/\n//gs;

            my $label = join " ", $id, $title;

            push @query_output,
              {
                'id'    => $id,
                'value' => "PMID:" . $id,
                'label' => $label
              };
        }
    }
    @query_output = sort { $a->{id} <=> $b->{id} } @query_output;

    # JSON OUTPUT
    print JSON::to_json(\@query_output);
}

sub retrieve_pmid_record {
    my ($arg_ref) = @_;

    my $response = {};

    # HTTP HEADER
    print $arg_ref->{cgi}->header(-type => 'application/json');

    my @query_output = ();
    my $pmid         = $arg_ref->{pmid};
    $pmid =~ s/^\s+|\s+$//gs;

    ## json response hashref
    my $response = {};

    my $lit      = 'medicago';
    my @attribs  = qw(author year title journal citation);
    my $lit_root = DB_ROOT . (DB_LITERATURE)->{$lit} . '/' . DB_TEXT;

    my $response = {};
    $response->{lit} = $lit;
    foreach my $attrib (@attribs) {
        my $attrib_value = undef;

        my $attrib_file = $lit_root . '/' . $attrib . '/' . $pmid;
        if (-e $attrib_file) {
            $attrib_value = `cat $attrib_file`;
            chomp $attrib_value;

            $attrib_value = InverseReplaceSpecChar($attrib_value);
            $attrib_value =~ s/\\//gs;
            $attrib_value =~ s/\n//gs;
            $attrib_value =~ s/\s+$//gs;

            if ($attrib eq "citation") {
                my ($vol, $issue, $page) = $attrib_value =~ /V\s*\:(.*)I\s*\:(.*)P\s*\:(.*)/;

                $vol   =~ s/^\s+|\s+$//gs;
                $issue =~ s/^\s+|\s+$//gs;
                $page  =~ s/^\s+|\s+$//gs;

                $vol   = ($vol)   ? $vol   : "NA";
                $issue = ($issue) ? $issue : "NA";
                $page  = ($page)  ? $page  : "NA";

                $response->{$attrib} = "$vol($issue):$page";
                $response->{locator} = QUERY_URI . $pmid;
            }
            else {
                $response->{$attrib} = $attrib_value;
            }
        }
    }
    if(scalar keys %{$response} <= 1) {
        $response->{error} = "Unable to process PMID: $pmid";
    }

    # JSON OUTPUT
    print JSON::to_json($response);
}

1;
