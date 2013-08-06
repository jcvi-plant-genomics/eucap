package EuCAP::Contact;
use strict;

use base 'Exporter';
our (@ISA, @EXPORT);

@ISA    = qw(Exporter);
@EXPORT = qw(send_email);

sub send_email {
    my ($arg_ref) = @_;

    my @addresses = ();
    push @addresses, "-c '$arg_ref->{cc_addr}'"  if (defined $arg_ref->{cc_addr});
    push @addresses, "-b '$arg_ref->{bcc_addr}'" if (defined $arg_ref->{bcc_addr});
    push @addresses, "$arg_ref->{to_addr}";

    my $send_cmd = "mailx -s '$arg_ref->{subject}' " . join(' ', @addresses);
    return 0 unless (open MAIL, "| $send_cmd");

    print MAIL <<_EOM_;
$arg_ref->{body}
_EOM_

    close MAIL;
    return 1;
}

1;