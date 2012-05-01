package Print_to_screen;

use strict;
use Switch;
use Exporter::Simple;
use Merge::HashRef;

use base 'Exporter';
our (@ISA, @EXPORT);

@ISA    = qw(Exporter);
@EXPORT = qw(output_to_jcvi_tmpl);

my $side_links   = "/opt/www/medicago/cgi-bin/medicago/medicago_links.txt";
my $gbrowsedb    = "medicago";
my $blastdb      = "mtbe";
my $site         = '<em>M. truncatula</em>';
my $project_name = '<table><tbody><tr>
<td><img src="/medicago/include/images/mtr_leaf.png" width=50px /></td>
<td style="color: white; ">&nbsp;Medicago truncatula Genome Project</td>
</tr></tbody></table>';

my $zone;
switch ($ENV{SERVER_NAME}) {
    case /dev/  { $zone = "-dev"; }
    case /test/ { $zone = "-test"; }
    else        { $zone = ""; }
}
my $side_menu = &get_side_links('Annotation');
my $top_menu  = &get_top_menu();

# Template files/Locations
my $two_column_fixed_width =
  '/usr/local/common/web' . $ENV{'WEBTIER'} . '/templates/perl/2_column_fixed_width.tpl';
my $two_column_fluid_width =
  '/usr/local/common/web' . $ENV{'WEBTIER'} . '/templates/perl/2_column_fluid_width.tpl';
my $home_page = '/cgi-bin/medicago/overview.cgi';

my $jcvi_template = $two_column_fixed_width;
my $title         = 'Medicago truncatula Genome Project :: Community Annotation';
my $project_name  = 'Medicago truncatula Community Annotation Portal';
my @breadcrumb    = ({ 'link' => $ENV{REQUEST_URI}, 'menu_name' => 'EuCAP' });
my @stylesheets =
  qw(https://ajax.googleapis.com/ajax/libs/jqueryui/1/themes/smoothness/jquery-ui.css /medicago/eucap/include/css/eucap.css /medicago/include/css/rounded_corners.css);
my @javascripts =
  qw(https://ajax.googleapis.com/ajax/libs/jquery/1/jquery.min.js http://ajax.googleapis.com/ajax/libs/jqueryui/1/jquery-ui.min.js /medicago/eucap/include/js/eucap.js /medicago/eucap/include/js/json.js /medicago/include/js/rounded_corners.js);
my $left_content = '
<table cellpadding="10px" cellspacing="10px">
    <tr>
        <td><a href="http://www.nsf.gov/" target="_blank"><IMG src="/medicago/include/images/nsf.jpg" border=0 width=50 height=50></a></td>
        <td>
            <a href="http://www.nsf.gov/awardsearch/showAward.do?AwardNumber=0321460" target="_blank">Award #0321460</a><br />
            <a href="http://www.nsf.gov/awardsearch/showAward.do?AwardNumber=0604966" target="_blank">Award #0604966</a><br />
            <a href="http://www.nsf.gov/awardsearch/showAward.do?AwardNumber=0821966" target="_blank">Award #0821966</a>
        </td>
    </tr>
</table>
<br />
<font>
    <span style="color: red;">Warning:</span>  This site uses <a href="http://en.wikipedia.org/wiki/Ajax_(programming)">AJAX</a>.
    Please don&apos;t press ymy browser&apos;s back button!
</font>';

my $jcvi_vars = {};
$jcvi_vars->{site}         = $site;
$jcvi_vars->{home_page}    = $home_page;
$jcvi_vars->{project_name} = $project_name;
$jcvi_vars->{side_menu}    = $side_menu;
$jcvi_vars->{left_content} = $left_content;
$jcvi_vars->{stylesheets}  = \@stylesheets;
$jcvi_vars->{javascripts}  = \@javascripts;
$jcvi_vars->{breadcrumb}   = \@breadcrumb;

sub output_to_jcvi_tmpl {
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

sub get_top_menu {
    open LINK, "<", $side_links or die "can't open $side_links\n";
    my @array = <LINK>;
    close LINK;

    my @top_menu = ();
    foreach my $line (@array) {
        chomp $line;
        next if (not $line or $line =~ /^#/);

        my ($name, $link);
        if ($line =~ /^\S+/) {
            ($name, $link) = split /\t/, $line;
            push @top_menu, { 'link' => $link, 'menu_name' => $name };
        }
    }

    return \@top_menu;
}

sub get_side_links {
    my ($section) = @_;

    open LINK, "<", $side_links or die "can't open $side_links\n";
    my @array = <LINK>;
    close LINK;

    my @side_menu = ();
    my $flag      = 0;
    foreach my $line (@array) {
        chomp $line;
        next if (not $line or $line =~ /^#/);
        if ($line =~ /\<.*\>/) {
            $line =~ s/\<ZONE\>/$zone/g;
            $line =~ s/\<BLASTDB\>/$blastdb/g;
            $line =~ s/\<DB\>/$gbrowsedb/g;
        }

        my ($name, $link);
        if ($line =~ /^\t\t\S+/ and $flag == 1) {
            $line =~ s/^\t\t//;
            ($name, $link) = split /\t/, $line;
            push @side_menu, { 'class' => 'subC', 'link' => $link, 'menu_name' => $name };
        }
        elsif ($line =~ /^\t\S+/ and $flag == 1) {
            $line =~ s/^\t//;
            ($name, $link) = split /\t/, $line;
            push @side_menu, { 'class' => 'subA', 'link' => $link, 'menu_name' => $name };
        }
        elsif ($line =~ /^\S+/) {
            ($name, $link) = split /\t/, $line;
            $flag = ($name eq $section) ? 1 : 0;
            push @side_menu, { 'class' => 'no_sub', 'link' => $link, 'menu_name' => $name };
        }
    }

    return \@side_menu;
}

1;
