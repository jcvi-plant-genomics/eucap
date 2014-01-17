package EuCAP::Print_to_screen;

use strict;
use Exporter::Simple;
use Merge::HashRef;

use base 'Exporter';
our (@ISA, @EXPORT);

@ISA    = qw(Exporter);
@EXPORT = qw(output_to_page_tmpl);

# Bootstrap template
my $bootstrap_template = "/opt/www/medicago/cgi-bin/eucap/tmpl/eucap.tpl";
my $jcvi_template = $bootstrap_template;

# Page variables
my $site         = '<em>M. truncatula</em>';
my $home_page = '/cgi-bin/medicago/overview.cgi';
my $project_name  = 'Medicago truncatula Community Annotation Portal';
my @breadcrumb    = ();
my @stylesheets =
  qw(/eucap/include/Aristo/Aristo.css /eucap/include/css/jcvi/main.css /eucap/include/css/eucap.css /eucap/include/css/rounded_corners.css);
my @javascripts =
  qw(https://ajax.googleapis.com/ajax/libs/jquery/1.7.2/jquery.js https://ajax.googleapis.com/ajax/libs/jqueryui/1.8.7/jquery-ui.js /eucap/include/js/eucap.js /eucap/include/js/json.js /eucap/include/js/rounded_corners.js);

my $jcvi_vars = {};
$jcvi_vars->{site}         = $site;
$jcvi_vars->{home_page}    = $home_page;
$jcvi_vars->{project_name} = $project_name;

$jcvi_vars->{stylesheets} = \@stylesheets;
$jcvi_vars->{javascripts} = \@javascripts;
$jcvi_vars->{breadcrumb}  = \@breadcrumb;

sub output_to_page_tmpl {
    my ($arg_ref) = @_;

    foreach my $feature ("javascripts", "stylesheets", "breadcrumb") {
        if (defined $arg_ref->{$feature}) {
            push @{ $jcvi_vars->{$feature} }, @{ $arg_ref->{$feature} };
            delete $arg_ref->{$feature};
        }
    }

    $jcvi_vars = Merge::HashRef->merge_hashref($jcvi_vars, $arg_ref);

    # Initialize JCVI template
    my $jcvi_tt = Template->new({ ABSOLUTE => 1, });
    $jcvi_tt->process($jcvi_template, $jcvi_vars) or die $jcvi_tt->error();
}

1;
