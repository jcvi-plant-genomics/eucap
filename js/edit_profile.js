$(document).ready(function(){
    $('#edit_profile').validate({
        rules: {
            username: {
                required: true,
                minlength: 4,
                remote: '/cgi-bin/medicago/eucap/eucap.pl?action=check_username&ignore=' + $('#orig_username').val()
            },
            name: {
                required: true,
                minlength: 2
            },
            email: {
                required: true,
                email: true,
                remote: '/cgi-bin/medicago/eucap/eucap.pl?action=check_email&ignore=' + $('#orig_email').val()
            },
            url: {
                required: false,
                url: true
            }
        },
        messages: {
            username: {
                required: 'Username cannot be empty',
                minlength: jQuery.format('Username must be at least {0} characters'),
                remote: jQuery.format('Username is taken')
            },
            name: {
                required: 'Name cannot be empty',
                minlength: jQuery.format('Name must be at least {0} characters'),
            },
            password: {
                required: 'Password cannot be empty',
                minlength: jQuery.format('Password must be at least {0} characters'),
            },
            email: {
                required: 'Email cannot be empty',
                email: 'Please enter a valid email address',
                remote: jQuery.format('Email {0} is already in use')
            },
            url: {
                url: 'Please enter a valid URL'
            }
        },
        errorLabelContainer: "#errorBox",
        wrapper: "li",
        submitHandler: function(form) {
            jQuery(form).ajaxSubmit({
                url:    '/cgi-bin/medicago/eucap/eucap.pl',
                type:   'POST',
                dataType: 'json',
                success: function(data, statusText, XMLHttpRequest) {
                    $('#update_status').removeClass('error success');
                    if(data.photo_file_name !== null) {
                        $('#user_photo').attr('src', '/medicago/eucap/include/images/ca_users/' + data.photo_file_name);
                        $('#update_status').addClass('success');
                    } else {
                        $('#update_status').addClass('error');
                    }
                    $('#update_status').html(data.update_status);
                },
            });

            return false;
        }
    });
});
