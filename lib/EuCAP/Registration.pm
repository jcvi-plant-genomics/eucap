package EuCAP::Registration;

use strict;
use Time::Piece;
use MIME::Base64 qw/encode_base64url/;

use EuCAP::DBHelper;
use EuCAP::Contact;
use EuCAP::Controller::User;

use base 'Exporter';
our (@ISA, @EXPORT);

@ISA    = qw(Exporter);
@EXPORT = qw(signup_page signup_user validate_new_user $PA_address $admin_address);

# Read the eucap.ini configuration file
my %cfg = ();
tie %cfg, 'Config::IniFiles', (-file => 'eucap.ini');

# Build the Admin email addresses
my $admin_address = $cfg{'email'}{'admin'};
my $PA_address    = $cfg{'email'}{'pa'};

sub signup_page {
    my ($cgi) = @_;
    my $body_tmpl = HTML::Template->new(filename => "./tmpl/signup_page.tmpl");

    print $cgi->header(-type => 'text/html');
    my $title = "Account Sign Up";

    my $page_vars = {};
    push @{ $page_vars->{javascripts} }, "/eucap/include/js/jquery.validate.min.js",
      "/eucap/include/js/jquery.form.js", "/eucap/include/js/signup_page.js";
    push @{ $page_vars->{breadcrumb} }, ({ 'link' => $ENV{REQUEST_URI}, 'menu_name' => $title });

    $page_vars->{login}       = 1;
    $page_vars->{title}       = "EuCAP :: $title";
    $page_vars->{page_header} = "EuCAP Account Sign Up";

    $page_vars->{main_content} = $body_tmpl->output;

    return $page_vars;
}

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
    my $page_vars = {};

    my $validate_info =
      cgi_to_hashref({ cgi => $cgi, table => 'registration_pending', id => undef });
    my $pending_user = selectrow(
        {
            table => 'registration_pending',
            where => { username => $validate_info->{username} }
        }
    );

    my $error_string;
    if (defined $pending_user) {
        if ($pending_user->validation_key eq $validate_info->{validation_key}) {
            promote_pending_user($pending_user);
            $error_string = 'Account activated successfully!';
        }
        else {
            $error_string =
                'Bad validation with username : <b>'
              . $validate_info->{username}
              . '</b> and validation_key : <b>'
              . $validate_info->{validation_key}
              . '</b>';
        }
    }
    else {
        if (
            defined selectrow(
                { table => 'users', where => { username => $validate_info->{username} } }))
        {
            $error_string = "You're already registered! Please login with your username and password.";
        }
    }
    $page_vars = login_page(
        {
            'cgi'          => $cgi,
            'error_string' => $error_string,
        }
    );

    return $page_vars;
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
