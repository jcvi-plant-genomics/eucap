$(document).ready(function(){
    $('#edit_profile').validate({
        rules: {
            username: {
                required: true,
                minlength: 4,
                remote: window.location.pathname + '?action=check_username&ignore=' + $('#orig_username').val()
            },
            name: {
                required: true,
                minlength: 2
            },
            email: {
                required: true,
                email: true,
                remote: window.location.pathname + '?action=check_email&ignore=' + $('#orig_email').val()
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
                url:    window.location.pathname,
                type:   'POST',
                dataType: 'json',
                success: function(data, statusText, XMLHttpRequest) {
                	var lc_email = data.email.toString().toLowerCase();
                	var user_photo_url = 'http://www.gravatar.com/avatar/' + String( md5( lc_email ) ) + '?d=identicon&r=PG';
                	
                	// update username, name, organization
                	$('#user_username').html(data.username);
                	$('#user_name').html(data.name);
                	$('#user_org').html(data.organization);                	
                	
                	// update email
					$('#user_email').attr('href', 'mailto:' + data.email);
                	$('#user_email').html(data.email);
                	e
                	// update website
                	$('#user_url').attr('href', data.url);
                	$('#user_url').html(data.url);
                	                	
                	// update photos
                	$('#user_photo').attr('src', user_photo_url + '&s=200');
                	$('#user_photo_thumb').attr('src', user_photo_url);
                	
                    $('#update_status').html(data.update_status);
                },
            });
            
			setTimeout(function() {
                $('#update_status').empty();
            }, 10000);
            
            return false;
        }
    });
    
    $('#update_passwd').validate({
        rules: {
            current_passwd: {
                required: true,
            },
            new_passwd: {
                required: true,
				minlength: 5
            },
            cnf_new_passwd: {
                required: true,
                equalTo: '#new_passwd',
                minlength: 5                
            },
        },
        messages: {
            current_passwd: {
                required: 'Current Password cannot be empty',
            },
            new_passwd: {
                required: 'Please provide a new password',
                minlength: jQuery.format("Your password must consist of at least {0} characters"),                
            },
            cnf_new_passwd: {
                required: 'Please reconfirm your new password',
                minlength: jQuery.format("Your password must consist of at least {0} characters"),
                equalTo: 'Please enter the same password as above'            	
            },
        },
        errorLabelContainer: "#passwd_errorBox",
        wrapper: "li",
        submitHandler: function(form) {
            jQuery(form).ajaxSubmit({
                url:    window.location.pathname,
                type:   'POST',
                dataType: 'json',
                success: function(data, statusText, XMLHttpRequest) {
                	$('#passwd_update_status').removeClass('success error');
                	
                	if(data.error == 1) {
                		$('#passwd_update_status').addClass('error');
                	} else {
                		$('#passwd_update_status').addClass('success');
                	}
                	
                    $('#passwd_update_status').html(data.update_status);
                },
            });
            
			setTimeout(function() {
                $('#passwd_update_status').empty();
            }, 10000);

            return false;
        }
    });    
});