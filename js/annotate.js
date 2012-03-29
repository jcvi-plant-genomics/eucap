// set up page overlay with loading animation
$(function(){
    $('<div id="overlay" class="transparent" />').css({
        position: 'fixed',
        top: 0,
        left: 0,
        width: '100%',
        height: '100%',
        background: 'white url(/medicago/eucap/include/images/loading_overlay.gif) no-repeat center'
    }).hide().appendTo('body');
});

// function that triggers the add_loci or add_alleles action with
// the input locus_list or allele_list respectively. possible optiobns:
// datatype: 'loci', 'alleles'
// elemtype: 'id', 'val'
// element  : id:'loci_list', id:'alleles_list'
function add_from_list(datatype, element, elemtype) {
    var action = 'add_' + datatype;
    var url = '/cgi-bin/medicago/eucap/eucap.pl?action=' + action;
    var params = '';
    if(elemtype === 'id') {
        params = datatype + '_list=' + $('#' + element).val();
    } else {
        params = datatype + '_list=' + element;
    }

    if(datatype === 'alleles') {
        params = params + '&mutant_id=' + $('#mutant_id').val();
    }

    var query = url + '&' + params;

    var feature = '';
    var status_span = datatype + '_add_status';
    $('#' + status_span).html('<img src="/medicago/eucap/include/images/loading.gif" />');

    $.ajax({
        url: url,
        data: params,
        success: function(data, textStatus, XMLHttpRequest) {
            $('#' + status_span).removeClass('error');
            $('#' + status_span).addClass('success');
            $('#' + status_span).html(data);

            if (datatype === 'loci') {
                window.location = '/cgi-bin/medicago/eucap/eucap.pl?action=annotate';
            } else if(datatype === 'alleles') {
                $('#get_alleles').delay(1000).queue(function(){
                    $('#annotate_alleles').dialog('close');
                    $(this).trigger("click");
                    $(this).dequeue();
                });
            }
        },
        error: function(XMLHttpRequest, textStatus, errorThrown) {
            $('#' + status_span).removeClass('success');
            $('#' + status_span).addClass('error');
            $('#' + status_span).html('Error in XMLHttpRequest: <a href="' + query + '">' + query + '</a>');
        }
    });
}

// add homologous loci determined by BLAST
function add_blast_loci( checkBoxClass ) {
    var selected_loci = [];
    var checkBoxes = $("input." + checkBoxClass + "[type=checkbox]");
    $.each(checkBoxes, function() {
        if ($(this).attr('checked')){
            selected_loci.push($(this).val());
        }
    });
    var new_loci = "";
    new_loci = selected_loci.join(",");

    add_from_list('loci', new_loci, 'val');
}

// delete a gene/allele from the gene/allele table. possible options:
// feature     : 'locus', 'allele'
// feature_id  : '1', '2'
// feature_name: gene_symbol or allele_name
function delete_feature(feature, feature_id, feature_name) {
    var url = '/cgi-bin/medicago/eucap/eucap.pl?action=delete_' + feature;
    var params = feature + '_id=' + feature_id;

    if(feature === 'allele') {
       params = params + '&mutant_id=' + $('#mutant_id').val();
    }

    var query = url + '&' + params;
    var status_span = feature + "_delete_status";
    $('#' + status_span).html('<img src="/medicago/eucap/include/images/loading.gif" />');

    $.ajax({
        url: url,
        data: params,
        success: function(data, textStatus, XMLHttpRequest) {
            if(data === 'Deleted!') {
                $('#' + status_span).removeClass('error');
                $('#' + status_span).addClass('success');
                $('#' + status_span).html('Deleted ' + feature + ' ' + feature_name);
                $('img.delete_' + feature + '_' + feature_id).closest('tr').fadeTo(400, 0, function () {
                    $(this).remove();
                });
                return false;
            } else {
                $('#' + status_span).removeClass('success');
                $('#' + status_span).addClass('error');
                $('#' + status_span).html('Error: Could not delete ' + feature + ' ' + feature_name);
            }
        },
        error: function(XMLHttpRequest, textStatus, errorThrown) {
            $('#' + status_span).html('Error in XMLHttpRequest: <a href="' + query + '">' + query + '</a>');
        }
    });
}

// Response messages for save_locus() and save_alleles()
// message[0] - for non admin users
// message[1] - for admin user
var message = new Array();
message[0] = 'Update success! Changes submitted for admin approval';
message[1] = 'Changes Approved!';

// save all the locus edits to database. remember to check if gene_symbol,
// gene_locus, and orig_functional_annotation are populated for a given
// locus. If mutant info is provided, make sure that mutant_symbol,
// phenotype, mutant_class_symbol and class_name are provided
function save_locus(locus_id) {
    var url = '/cgi-bin/medicago/eucap/eucap.pl?action=save_locus';
    if ( $('#mutant_symbol').val() === 'Search mutants...') {
        $('#mutant_symbol').val("");
    }

    var status_span = "locus_save_status";
    var params_arr = $('#locus_annotate').serializeArray();

    var req_locus_fields = new Array();
    req_locus_fields['gene_symbol'] = 1;
    req_locus_fields['gb_genomic_acc'] = 1;
    req_locus_fields['gb_cdna_acc'] = 1;
    req_locus_fields['gb_protein_acc'] = 1;
    req_locus_fields['reference_pub'] = 1;
    var track = 0;
    $.each(params_arr, function(i, params_arr){
        if(req_locus_fields[params_arr.name] === 1 && params_arr.value !== "") {
            track += 1;
        }
    });

    if(track >= 3) {
        $('#gene_symbol').removeClass('ui-state-error');
        $('#gb_genomic_acc, #gb_cdna_acc, #gb_protein_acc').removeClass('ui-state-error');
        $('#reference_pub').removeClass('ui-state-error');

        var req_mutant_info_fields = new Array();
        req_mutant_info_fields['mutant_symbol'] = 1;
        req_mutant_info_fields['mutant_class_symbol'] = 1;
        req_mutant_info_fields['mutant_class_name'] = 1;
        req_mutant_info_fields['mutant_phenotype'] = 1;
        req_mutant_info_fields['mutant_reference_pub'] = 1;
        track = 0;

        $.each(params_arr, function(i, params_arr){
            if(req_mutant_info_fields[params_arr.name] === 1 && params_arr.value !== "") {
                track += 1;
            }
        });

        if(track === 5 || track === 0) {
            $('#mutant_symbol').removeClass('ui-state-error');
            $('#mutant_class_symbol').removeClass('ui-state-error');
            $('#mutant_class_name').removeClass('ui-state-error');
            $('#mutant_phenotype').removeClass('ui-state-error');
            $('#mutant_reference_pub').removeClass('ui-state-error');

            var params = $('#locus_annotate').serialize();
            var query = url + '&' + params;
            $('#' + status_span).removeClass('ui-state-error');
            $('#' + status_span).addClass('success');
            $('#' + status_span).html('<img src="/medicago/eucap/include/images/loading.gif" />');

            $.ajax({
                type: 'POST',
                url: url,
                data: params,
                dataType: 'json',
                success: function(data, textStatus, XMLHttpRequest) {
                    if(data.updated === 1) {
                        $('#mod_date').val(data.mod_date);
                        $('#locus_mod_date').html('Last Modified date: <b>' + data.mod_date + '</b>');

                        if(data.updated_mutant === 1) {
                            $('#mutant_id').val(data.mutant_id);
                            $('#mutant_mod_date').val(data.mutant_mod_date);

                            var button_label = (data.has_alleles > 0) ? "Edit" : "Add";
                            $('#disp_get_alleles').html(
                                '<input type="button" id="get_alleles" name="get_alleles"'
                                + ' value="' + button_label
                                + '" onclick="perform_action(\'annotate_alleles\', \'mutant_id\', '
                                + data.mutant_id + ')" />'
                            );
                        }

                        if(data.updated_mutant_class === 1) {
                            $('mutant_class_id').val(data.mutant_class_id);
                        }

                        var msg = message[0];
                        if(data.locus_edits !== 1) {
                            remove_edits_highlight(data.locus_id, 'locus');
                            msg = message[1];
                        }
                        if(data.mutant_edits !== 1) {
                            remove_edits_highlight(data.mutant_id, 'mutant');
                            msg = message[1];
                        }
                        if(data.mutant_class_edits !== 1) {
                            remove_edits_highlight(data.mutant_class_id, 'mutant_class');
                            msg = message[1];
                        }

                        $('#' + status_span).html(msg);
                        update_locus_table(locus_id);
                    } else {
                        $('#' + status_span).html('No changes to update.');
                    }

                    $('#get_alleles').prop('disabled', false);
                },
                error: function(XMLHttpRequest, textStatus, errorThrown) {
                    $('#' + status_span).html('Error in XMLHttpRequest: <a href="' + query + '">' + query + '</a>');
                }
            });
        } else {
             $('#' + status_span).removeClass('success');
             $('#' + status_span).addClass('error');
             $('#' + status_span).html('Mutant Symbol, Class Symbol, Expansion, Phenotype and Publication are mandatory! Please fill out these fields.');

             $('#mutant_symbol').addClass('ui-state-error');
             $('#mutant_class_symbol').addClass('ui-state-error');
             $('#mutant_class_name').addClass('ui-state-error');
             $('#mutant_phenotype').addClass('ui-state-error');
             $('#mutant_reference_pub').addClass('ui-state-error');
        }
    } else {
        $('#' + status_span).removeClass('success');
        $('#' + status_span).addClass('ui-state-error');
        $('#' + status_span).html('Gene Symbol, Any one of the GenBank Accessions and Reference Publication are mandatory! Please fill out these fields.');

        $('#gene_symbol').addClass('ui-state-error');
        $('#gb_genomic_acc, #gb_cdna_acc, #gb_protein_acc').addClass('ui-state-error');
        $('#reference_pub').addClass('ui-state-error');
    }
    return false;
}

// save all the alleles from the form
function save_alleles(mutant_id) {
    var url = '/cgi-bin/medicago/eucap/eucap.pl?action=save_alleles';

    var status_span = "alleles_save_status";
    var params = $('#alleles_annotate').serialize();

    var query = url + '&' + params;
    $('#' + status_span).html('<img src="/medicago/eucap/include/images/loading.gif" />');

    $.ajax({
        type: 'POST',
        url: url,
        data: params,
        success: function(data, textStatus, XMLHttpRequest) {
            if(data.updated === 1) {
                $('#' + status_span).removeClass('error');
                $('#' + status_span).addClass('success');
                var msg = message[0];
                if(data.allele_edits !== 1) {
                    msg = message[1];
                }
                $('#' + status_span).html(msg);
            } else {
                $('#' + status_span).html('No changes to update.');
            }
        },
        error: function(XMLHttpRequest, textStatus, errorThrown) {
            $('#' + status_span).removeClass('success');
            $('#' + status_span).addClass('error');
            $('#' + status_span).html('Error in XMLHttpRequest: <a href="' + query + '">' + query + '</a>');
        }
    });
    return false;
}

// update the locus_table
function update_locus_table(locus_id) {
    $('#gene_symbol_' + locus_id).html($('#gene_symbol').val());
    $('#func_annotation_' + locus_id).html($('#func_annotation').val());
    $('#gene_locus_' + locus_id).html($('#gene_locus').val());
    $('#orig_func_annotation_' + locus_id).html($('#orig_func_annotation').val());
    $('#comment_' + locus_id).html($('#comment').val());
}

// remove edits highlighting
function remove_edits_highlight(id, prefix) {
    $('.' + prefix + '_' + id).removeClass('tableRowEdit');
    $('.' + prefix + '_' + id).addClass('tableRowOdd');
}

// perform action: make ajax GET call to eucap.pl with action and id as params
// if (param === id) or (param === ''), make ajax GET call with single parameter,
// else, make ajax POST call by serializing all form input elements
function perform_action(action, param_name, param) {
    if(action !== '' && param_name === undefined && param === undefined) {
        param  = action;
        action = $('#'+ action + '_form input[name=action]').val();
    }
    var url = '/cgi-bin/medicago/eucap/eucap.pl?action=' + action;

    var type = '';
    var params = '';
    if(typeof param === 'number') {
        params = param_name + '=' + param;
        type = 'GET';
    } else if(param === '') {
       params = param_name + '=' + $('#' + param_name).val()
        type = 'GET';
    } else {
        params = $('#' + param + '_form').serialize();
        type = 'POST';
    }

    var query = url + '&' + params;

    if(action === 'annotate_alleles' || action === 'struct_anno') {
        $('#overlay').show();
        $('#' + action).dialog({
            autoOpen: false,
            modal: true,
            width: 800,
            closeOnEscape: false
        });
    } else {
        $('#' + action).html('<img src="/medicago/eucap/include/images/loading.gif" /><p class="bodytext">Loading</p>');
    }

    $.ajax({
        type: type,
        url: url,
        data: params,
        success: function(data, textStatus, XMLHttpRequest) {
            if(action === 'submit_struct_anno') {
                $('#' + action).removeClass('error');
                $('#' + action).addClass('success');
            }
            $('#' + action).html(data);

            if(action === 'annotate_alleles' || action === 'struct_anno') {
                $('#overlay').hide();
                $('#' + action).dialog('open');
                $('#' + action).addClass('panel_background');
            }

            if(action !== 'submit_struct_anno') {
                goToByScroll(action);
            }
        },
        error: function(XMLHttpRequest, textStatus, errorThrown) {
            $('#' + action).html('Error in XMLHttpRequest: <a href="' + query + '">' + query + '</a><br />textStatus: ' + textStatus + '<br />errorThrown: ' + errorThrown);
        }
    });
    return false;
}

// Utility functions
// clear the 'save_status' span. used when invoking the 'Reset' button
function clear_status(feature) {
    $('#' + feature + '_save_status').removeClass('success error');
    $('#' + feature + '_save_status').html("");
}

// toggle one or a pair of panels
function toggle_panel(panel_id, other_panel_id) {
    if( ! $('#' + other_panel_id).hasClass('hide_panel') ) {
        $('#' + other_panel_id).addClass('hide_panel');
    }
    $('#' + panel_id).toggleClass('hide_panel');
    goToByScroll(panel_id);
}

// remove a certain div
function clear_div(id) {
    $('#' + id).empty();
}

// close a certain panel on click
function close_panel_and_scroll(panel_to_close, panel_to_scroll_to) {
    clear_div(panel_to_close);
    goToByScroll(panel_to_scroll_to);
}

// close a certain dialog
function close_dialog_and_scroll(dialog_to_close, panel_to_scroll_to) {
    $('#' + dialog_to_close).dialog('close');
    goToByScroll(panel_to_scroll_to);
}

// scroll to a certain anchor on the page
function goToByScroll(id){
    $('html,body').animate({scrollTop: $("#"+id).offset().top}, 'slow');
}

// check all checkboxes belonging to a certain div/span id
function check_all( id, checkbox_class ) {
    $("." + checkbox_class).attr('checked', $('#' + id).is(':checked'));
}

// perform a redirect based on a specific 'action'
function redirect(action) {
    window.location = '/cgi-bin/medicago/eucap/eucap.pl?action=' + action;
}