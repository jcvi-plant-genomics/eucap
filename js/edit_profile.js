// jquery widget to augment .keyup() (onDelayedKeyup)
(function($){
    $.widget('ui.onDelayedKeyup', {
        _init : function() {
            var self = this;
            $(this.element).keyup(function() {
                if(typeof(window['inputTimeout']) != 'undefined'){
                    window.clearTimeout(inputTimeout);
                }
                var handler = self.options.handler;
                window['inputTimeout'] = window.setTimeout(function() { handler.call(self.element) }, self.options.delay);
            });
        },
        options: {
            handler: $.noop(),
            delay: 500
        }
    });
})(jQuery);

$(function() {
    $('#username').onDelayedKeyup( {
        handler: function() {
            $('#username_err_msg').html('');
            $('#username_err_msg').removeClass('success error');
            if($(this).val() !== '' &&
               $(this).val().length > 4 &&
               $(this).val() !== $('#orig_username').val()) {
                var user_id = $('#user_id').val();
                validate_username(user_id, $(this).val());
            }
        }
    });
});

$(function() {
    $('#email').onDelayedKeyup( {
        handler: function() {
            $('#email_err_msg').html('');
            $('#email_err_msg').removeClass('success error');
            if($(this).val().length !== 0 &&
               $(this).val() !== $('#orig_email').val()) {
                validate_email($(this).val());
            }
        }
    });
});

$(function() {
    $('#url').onDelayedKeyup( {
        handler: function() {
            $('#url_err_msg').html('');
            $('#url_err_msg').removeClass('success error');
            if($(this).val().length !== 0 &&
               $(this).val() !== $('#orig_url').val()) {
                validate_url($(this).val());
            }
        }
    });
});

function validate_username(user_id, username) {
    var url = '/cgi-bin/medicago/eucap2/eucap.pl?action=check_username';
    var params = 'user_id=' + user_id + '&username=' + username;
    var query = url + '&' + params;

    $.ajax({
        url: url,
        data: params,
        success: function(data, textStatus, XMLHttpRequest) {
            if(data.available === 1) {
                $('#username_err_msg').removeClass('error');
                $('#username_err_msg').addClass('success');
            } else {
                $('#username_err_msg').removeClass('success');
                $('#username_err_msg').addClass('error');
            }
            $('#username_valid').val(data.available);
            $('#username_err_msg').html(data.message);
        },
        error: function(XMLHttpRequest, textStatus, errorThrown) {
            $('#username_err_msg').removeClass('success error');
            $('#username_err_msg').html('Error in XmlHttpRequest: <a href="' + query + '">' + query + '</a>');
        }
    });
}

function validate_email(email_address) {
    var filter = /^[a-zA-Z0-9_.-]+@[a-zA-Z0-9]+[a-zA-Z0-9.-]+[a-zA-Z0-9]+.[a-z]{0,4}$/;
    if(filter.test(email_address)) {
        $('#email_err_msg').html('Valid!');
        $('#email_err_msg').addClass('success');
        $('#email_valid').val('1');
    } else {
        $('#email_err_msg').html('Invalid!');
        $('#email_err_msg').addClass('error');
        $('#email_valid').val('0');
    }
}

function validate_url(url) {
    var urlregex = new RegExp("^(http|https|ftp)\://([a-zA-Z0-9\.\-]+(\:[a-zA-Z0-9\.&amp;%\$\-]+)*@)*((25[0-5]|2[0-4][0-9]|[0-1]{1}[0-9]{2}|[1-9]{1}[0-9]{1}|[1-9])\.(25[0-5]|2[0-4][0-9]|[0-1]{1}[0-9]{2}|[1-9]{1}[0-9]{1}|[1-9]|0)\.(25[0-5]|2[0-4][0-9]|[0-1]{1}[0-9]{2}|[1-9]{1}[0-9]{1}|[1-9]|0)\.(25[0-5]|2[0-4][0-9]|[0-1]{1}[0-9]{2}|[1-9]{1}[0-9]{1}|[0-9])|([a-zA-Z0-9\-]+\.)*[a-zA-Z0-9\-]+\.(com|edu|gov|int|mil|net|org|biz|arpa|info|name|pro|aero|coop|museum|[a-zA-Z]{2}))(\:[0-9]+)*(/($|[a-zA-Z0-9\.\,\?\'\\\+&amp;%\$#\=~_\-]+))*$");

    if(urlregex.test(url)) {
        $('#url_err_msg').html('Valid!');
        $('#url_err_msg').addClass('success');
        $('#url_valid').val('1');
    } else {
        $('#url_err_msg').html('Invalid!');
        $('#url_err_msg').addClass('error');
        $('#url_valid').val('0');
    }
}
