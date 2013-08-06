$(document).ready(function(){
    $('#create_user').validate({
        rules: {
            password: {
                required: true,
                minlength: 5
            },
            confirm_password: {
                required: true,
                minlength: 5,
                equalTo: '#password'
            },
        },
        messages: {
            password: {
                required: 'Please provide a new password',
                minlength: jQuery.format("Your password must consist of at least {0} characters"),
            },
            confirm_password: {
                required: 'Please reconfirm your new password',
                minlength: jQuery.format("Your password must consist of at least {0} characters"),
                equalTo: 'Please enter the same password as above'
            },
        },
        submitHandler: function(form) {
            jQuery(form).ajaxSubmit({
                target: "#reset_status",
                url:    window.location.pathname,
                type:   'POST'
            });

            return false;
        }
    });
});
