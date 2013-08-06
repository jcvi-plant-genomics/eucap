package EuCAP::Registration;

use strict;
use EuCAP::DBHelper;
use EuCAP::Contact;

use base 'Exporter';
our (@ISA, @EXPORT);

@ISA    = qw(Exporter);
@EXPORT = qw(signup_user validate_new_user $PA_address $admin_address);

# Read the eucap.ini configuration file
my %cfg = ();
tie %cfg, 'Config::IniFiles', (-file => 'eucap.ini');

# Build the Admin email addresses
my $email_domain = $cfg{'email'}{'domain'};
my $admin        = $cfg{'email'}{'admin'};
my $admin_address = $admin . "\@" . $email_domain;

sub signup_user {
    my ($cgi) = @_;

    my $user_info = cgi_to_hashref({ cgi => $cgi, table => 'users', id => undef });

    my $crypt_obj =
      Authen::Passphrase::MD5Crypt->new(salt_random => 1, passphrase => $user_info->{password})
      or die;
    $user_info->{salt} = $crypt_obj->salt;
    $user_info->{hash} = $crypt_obj->hash_base64;

    delete $user_info->{password};
    eval {
        $user_info->{validation_key} = validation_hash($user_info);
        my $pending_user_row = do('insert', 'registration_pending', $user_info);
    };

    if ($@) {
        die "Registration Error. Please notify site administrator ($admin_address): $@\n\n";
    }

    my $tmpl = HTML::Template->new(filename => "./tmpl/email_body_new.tmpl");
    my $validation_url = URI->new(join "", 'http://', $ENV{'HTTP_HOST'}, $ENV{'SCRIPT_NAME'});
    $validation_url->query_form(
        'action'         => 'validate_new_user',
        'username'       => $user_info->{username},
        'validation_key' => $user_info->{validation_key}
    );
    $tmpl->param(validation_url => $validation_url);
    my $email_body = $tmpl->output;

    my $success = send_email(
        {
            to_addr  => $user_info->{email},
            bcc_addr => $admin_address,
            subject  => '[EuCAP] New User Registration',
            body     => $email_body
        }
    );

    print $cgi->header(-type => 'text/plain');
    ($success)
      ? print 'Success! Please check your email for confirmation.'
      : print 'Error: Please notify website administrator';
}

sub validate_new_user {
    my ($cgi) = @_;

    my $validate_info =
      cgi_to_hashref({ cgi => $cgi, table => 'registration_pending', id => undef });
    my $pending_user = selectrow(
        {
            table => 'registration_pending',
            where => { username => $validate_info->{username} }
        }
    );
    if (defined $pending_user
        and $pending_user->validation_key eq $validate_info->{validation_key})
    {
        promote_pending_user($pending_user);
        login_page(1, 'Account activated successfully');
    }
    else {
        login_page(1,
                "Bad validation using username="
              . $cgi->param('username')
              . "and validation_key="
              . $cgi->param('validation_key'));
    }
}

sub promote_pending_user {
    my ($pending_user) = @_;

    eval {
        my $new_user = do(
            'insert', 'users',
            {
                name         => $pending_user->name,
                email        => $pending_user->email,
                username     => $pending_user->username,
                salt         => $pending_user->salt,
                hash         => $pending_user->hash,
                url          => $pending_user->url,
                organization => $pending_user->organization
            }
        );

        $pending_user->delete;
    };

    if ($@) {
        die "Error: Couldn't activate user. Please notify site administrator: $@\n\n";
    }
}

sub validation_hash {
    my ($user_info) = @_;

    my $t        = localtime;
    my $h        = Digest->new('SHA-1');
    my $hash_str = join " ", $user_info->{email}, $ENV{'REMOTE_ADDR'}, $user_info->{salt},
      $t->datetime;
    my $hash_str_base64 = encode_base64url($hash_str);
    $h->add($hash_str_base64);

    return $h->hexdigest;
}

1;