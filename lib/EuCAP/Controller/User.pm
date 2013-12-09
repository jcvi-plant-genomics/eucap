package EuCAP::Controller::User;

use strict;
use EuCAP::DBHelper;
use Digest::MD5 qw/md5_hex/;

use base 'Exporter';
our (@ISA, @EXPORT);

@ISA    = qw(Exporter);
@EXPORT = qw(login_page check_email check_username update_password edit_profile logout);

sub login_page {
    my ($arg_ref) = @_;
    my $body_tmpl = HTML::Template->new(filename => "./tmpl/login.tmpl");
    if ($arg_ref->{error_string}) {
        $body_tmpl->param(error        => 1);
        $body_tmpl->param(error_string => $arg_ref->{error_string});
    }
    print $arg_ref->{cgi}->header(-type => 'text/html');

    my $title = "Eukaryotic Community Annotation Package";

    my $page_vars = {};
    $page_vars->{login}       = 1;
    $page_vars->{title}       = "EuCAP :: $title";
    $page_vars->{page_header} = $title;

    $page_vars->{main_content} = $body_tmpl->output;

    return $page_vars;
}

sub logout {
    my ($session, $cgi) = @_;
    $session->clear(["~logged_in"]);
    $session->flush;

    my $page_vars = login_page({
        'cgi' => $cgi,
        'error_string' => 'Logged out - Thank you!'
    });

    return $page_vars;
}

sub check_email {
    my ($cgi, $email, $ignore) = @_;

    #print $cgi->header(-type => 'application/json');
    print $cgi->header(-type => 'text/plain');

    my @results   = ();
    my $all_users = selectall_iter('users');
    while (my $user = $all_users->next()) {
        next if (defined $ignore and lc $ignore eq lc $user->email);
        if (lc $email eq lc $user->email) {
            print "false";

            #print JSON::to_json({ 'available' => 0, 'message' => 'Taken!' });
            exit;
        }
    }

    print "true";

    #print JSON::to_json({ 'available' => 1, 'message' => 'Available!' });
}

sub check_username {
    my ($cgi, $username, $user_id, $ignore) = @_;

    #print $cgi->header(-type => 'application/json');
    print $cgi->header(-type => 'text/plain');

    my @results   = ();
    my $all_users = selectall_iter('users');
    while (my $user = $all_users->next()) {
        next if (defined $user_id and $user_id == $user->user_id);
        next if (defined $ignore and $ignore eq $user->username);

        if ($username eq $user->username) {
            print "false";

            #print JSON::to_json({ 'available' => 0, 'message' => 'Taken!' });
            exit;
        }
    }

    print "true";

    #print JSON::to_json({ 'available' => 1, 'message' => 'Available!' });
}

sub update_password {
    my ($session, $cgi) = @_;

    my $user_id  = $cgi->param('user_id');
    my $password = $cgi->param('current_passwd');
    my $new_password = $cgi->param('new_passwd');

    my $user     = selectrow({ table => 'users', where => { user_id => $user_id } });

    my $salt      = $user->salt;
    my $hash      = $user->hash;
    my $crypt_obj = Authen::Passphrase::MD5Crypt->new(salt => $salt, hash_base64 => $hash);

    my $response = {};
    if ($crypt_obj->match($password)) {
        my $user_info = {};
        my $new_crypt_obj =
          Authen::Passphrase::MD5Crypt->new(salt_random => 1, passphrase => $new_password)
          or die;

        $user_info->{salt} = $new_crypt_obj->salt;
        $user_info->{hash} = $new_crypt_obj->hash_base64;

        do('update', 'users',
            {
                'hashref' => $user_info,
                'obj'     => $user,
            }
        );

        $response->{'update_status'} = 'Password updated!';
        $response->{'error'} = undef;
    }
    else {
        $response->{'update_status'} = 'Old Password does not match! Please try again';
        $response->{'error'} = 1;
    }

    print $session->header(-type => 'application/json');
    print JSON::to_json($response);
}

sub edit_profile {
    my ($session, $cgi, $save) = @_;
    my $title    = "Edit User Profile";
    my $anno_ref = $session->param('anno_ref');

    my $user_id = (defined $anno_ref->{is_admin}) ? 0 : $anno_ref->{user_id};
    my $user_obj = selectrow({ table => 'users', primary_key => $user_id });

    my $username      = $anno_ref->{users}->{$user_id}->{username};
    my $update_status = "";

    if ($save) {
        my $user_id          = $cgi->param('user_id');
        my $new_username     = $cgi->param('username');
        my $new_name         = $cgi->param('name');
        my $new_organization = $cgi->param('organization');
        my $new_email        = $cgi->param('email');
        my $new_url          = $cgi->param('url');

        my $response = {};

        $anno_ref->{users}->{$user_id}->{username}        = $new_username;
        $anno_ref->{users}->{$user_id}->{name}            = $new_name;
        $anno_ref->{users}->{$user_id}->{organization}    = $new_organization;
        $anno_ref->{users}->{$user_id}->{email}           = $new_email;
        $anno_ref->{users}->{$user_id}->{url}             = $new_url;

        do(
            'update', 'users',
            {
                hashref => $anno_ref->{users}->{$user_id},
                obj     => $user_obj
            }
        );

        #update_info({ user_id => $user_id, anno_ref => $anno_ref, table => 'users' });
        $update_status             = 'Profile updated!';
        $response->{username}        = $new_username;
        $response->{name}            = $new_name;
        $response->{organization}    = $new_organization;
        $response->{email}           = $new_email;
        $response->{url}             = $new_url;

        $response->{error}           = undef;
        $response->{update_status}   = $update_status;

        print $session->header(-type => 'application/json');
        print JSON::to_json($response);
    }
    else {
        my $page_vars = {};

        my $body_tmpl = HTML::Template->new(filename => "./tmpl/edit_profile.tmpl");
        $body_tmpl->param(
            user_id         => $user_id,
            username        => $anno_ref->{users}->{$user_id}->{username},
            name            => $anno_ref->{users}->{$user_id}->{name},
            organization    => $anno_ref->{users}->{$user_id}->{organization},
            email           => $anno_ref->{users}->{$user_id}->{email},
            url             => $anno_ref->{users}->{$user_id}->{url},
            email_hash      => md5_hex($anno_ref->{users}->{$user_id}->{email}),
        );
        print $session->header;

        push @{ $page_vars->{javascripts} },
          "/eucap/include/js/jquery.validate.min.js",
          "/eucap/include/js/jquery.form.js",
          "/eucap/include/js/md5.min.js",
          "/eucap/include/js/edit_profile.js";
        push @{ $page_vars->{breadcrumb} },
          (
            {
                'link'      => '/cgi-bin/eucap/eucap.pl?action=dashboard',
                'menu_name' => 'Dashboard'
            },
            { 'link' => $ENV{REQUEST_URI}, 'menu_name' => $title }
          );
        $page_vars->{title}    = "EuCAP :: $title";
        $page_vars->{is_family_editor} = 1 if(defined $anno_ref->{is_family_editor});
        $page_vars->{user_info} = {
                'username'     => $username,
                'name'         => $anno_ref->{users}->{$user_id}->{name},
                'organization' => $anno_ref->{users}->{$user_id}->{organization},
                'email'        => $anno_ref->{users}->{$user_id}->{email},
                'url'          => $anno_ref->{users}->{$user_id}->{url},
                'email_hash'   => md5_hex($anno_ref->{users}->{$user_id}->{email}),
        };
        $page_vars->{main_content} = $body_tmpl->output;

        return $page_vars;
    }
}

1;
