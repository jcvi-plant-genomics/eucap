$(document).ready(function(){
    $('#create_user').validate({
        rules: {
            name: {
                required: true,
                minlength: 2
            },
            username: {
                required: true,
                minlength: 4,
                remote: '/cgi-bin/medicago/eucap/eucap.pl?action=check_username'
            },
            password: {
                required: true,
                minlength: 5
            },
            confirm_password: {
                required: true,
                minlength: 5,
                equalTo: '#password'
            },
            email: {
                required: true,
                email: true,
                remote: '/cgi-bin/medicago/eucap/eucap.pl?action=check_email'
            },
            confirm_email: {
                required: true,
                email: true,
                equalTo: '#email'
            },
            url: {
                required: false,
                url: true
            }
        },
        messages: {
            name: {
                required: 'Please enter your full name',
                minlength: jQuery.format("You name must consist of atleast {0} characters"),
            },
            username: {
                required: 'Please enter a username',
                minlength: jQuery.format("Your username must consist of at least {0} characters"),
                remote: jQuery.format("{0} is already in use")
            },
            password: {
                required: 'Please provide a password',
                minlength: jQuery.format("Your password must consist of at least {0} characters"),
            },
            confirm_password: {
                required: 'Please reconfirm your password',
                minlength: jQuery.format("Your password must consist of at least {0} characters"),
                equalTo: 'Please enter the same password as above'
            },
            email: {
                required: 'Please provide an email address',
                email: 'Please enter a valid email address',
                remote: jQuery.format("{0} is already in use")
            },
            confirm_email: {
                required: 'Please reconfirm your email address',
                email: 'Please reconfirm your email address',
                equalTo: 'Please enter the same email address as above'
            },
            url: {
                url: 'Please enter a valid URL'
            }
        },
        submitHandler: function(form) {
            jQuery(form).ajaxSubmit({
                target: "#signup_status",
                url:    '/cgi-bin/medicago/eucap/eucap.pl',
                type:   'POST'
            });

            return false;
        }
    });
});
