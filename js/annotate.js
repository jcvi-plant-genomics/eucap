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
// datatype: 'loci', 'mutants', 'alleles'
// elemtype: 'id', 'val'
// element  : id:'loci_list', id:'mutant_list', id:'alleles_list'
function add_from_list(datatype, element, elemtype) {
    var action = 'add_' + datatype;
    var url = '/cgi-bin/medicago/eucap/eucap.pl?action=' + action;
    var params = '';
    if(elemtype === 'id') {
        params = datatype + '_list=' + $('#' + element).val();
    } else {
        params = datatype + '_list=' + element;
    }

    var user_id = undefined,
        mutant_id = undefined,
        mutant_class_id = undefined,
        family_id = undefined;

    if(datatype === 'alleles') {
        mutant_id = $('#mutant_id').val();
        params = params + '&mutant_id=' + mutant_id;
    } else if(datatype === 'mutants') {
        user_id = $('#user_id').val();
        mutant_class_id = $('#mutant_class_id').val();
        params = params + '&mutant_class_id=' + mutant_class_id;
    } else if(datatype === 'loci') {
        user_id = $('#user_id').val();
        family_id = $('#family_id').val();
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

            setTimeout(function() {
                $('#' + status_span).empty();
            }, 10000);

            if (datatype === 'loci') {
                var form = $('<form />');
                form.attr('id', 'annotate_family')
                    .attr('action', '/cgi-bin/medicago/eucap/eucap.pl')
                    .attr('method', 'POST')
                    .append('<input type="hidden" id="action" name="action" value="annotate" />')
                    .append('<input type="hidden" id="user_id" name="user_id" value="' + user_id + '" />')
                    .append('<input type="hidden" id="family_id" name="family_id" value="' + family_id + '" />')
                    .appendTo(document.body);
                setTimeout(function() {
                    form.submit().remove();
                }, 0);

                //window.location = '/cgi-bin/medicago/eucap/eucap.pl?action=annotate';
            } else if (datatype === 'mutants') {
                var form = $('<form />');
                form.attr('id', 'annotate_mutant_class')
                    .attr('action', '/cgi-bin/medicago/eucap/eucap.pl')
                    .attr('method', 'POST')
                    .append('<input type="hidden" id="action" name="action" value="annotate_mutants" />')
                    .append('<input type="hidden" id="user_id" name="user_id" value="' + user_id + '" />')
                    .append('<input type="hidden" id="mutant_class_id" name="mutant_class_id" value="' + mutant_class_id + '" />')
                    .appendTo(document.body);
                setTimeout(function() {
                    form.submit().remove();
                }, 0);

                //params = '&mutant_class_id=' + mutant_class_id + '&user_id=' + user_id;
                //window.location = '/cgi-bin/medicago/eucap/eucap.pl?action=annotate_mutants' + params;
            }
            else if(datatype === 'alleles') {
                $('#num_alleles_' + mutant_id).html(data.has_alleles);
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

// delete a gene/mutant_class/mutant/allele from the gene/mutant_class/mutant_info/allele table. possible options:
// feature     : 'locus', 'mutant', 'mutant_class', 'allele'
// feature_id  : '1', '2',  etc.
// feature_name: gene_symbol or mutant_symbol or mutant_class_symbol or allele_name
function delete_feature(feature, feature_id, feature_name) {
    var url = '/cgi-bin/medicago/eucap/eucap.pl?action=delete_' + feature;
    var params = feature + '_id=' + feature_id;

    if(feature === 'allele') {
       params = params + '&mutant_id=' + $('#mutant_id').val();
    } else if(feature === 'mutant') {
       params = params + '&mutant_class_id=' + $('#mutant_class_id').val();
    }

    var query = url + '&' + params;
    var status_span = feature + "_delete_status";
    var deleted_table = "deleted_" + feature + "_table";
    $('#' + status_span).html('<img src="/medicago/eucap/include/images/loading.gif" />');

    $.ajax({
        url: url,
        data: params,
        success: function(data, textStatus, XMLHttpRequest) {
            if(data === 'Deleted!') {
                // close any open edit panel
                if(feature === 'locus' || feature === 'mutant') {
                    close_panel_and_scroll('annotate_' + feature, undefined);
                }

                $('#' + status_span).removeClass('error');
                $('#' + status_span).addClass('success');
                $('#' + status_span).html('Deleted ' + feature + ' ' + feature_name);

                var deleted_row = $('img.delete_' + feature + '_' + feature_id).closest('tr').clone();
                $('img.delete_' + feature + '_' + feature_id).closest('tr').fadeTo(400, 0, function () {
                    $(this).remove();
                });

                deleted_row.find('img.delete_' + feature + '_' + feature_id)
                    .attr('src', '/medicago/eucap/include/images/undelete.png')
                    .attr('alt', function(i, val) { return 'un' + val; })
                    .attr('title', function(i, val) { return 'un' + val; })
                    .attr('onclick', function(i, val) { return 'un' + val; })
                    .attr('class', function(i, val) { return 'un' + val; });

                deleted_row.find('input#annotate_' + feature + '_' + feature_id).prop('disabled', true);
                deleted_row.find('input#annotate_' + feature + '_members_' + feature_id).prop('disabled', true);

                var num_deleted_rows = $('#' + deleted_table + ' tr').length;
                if(num_deleted_rows === 0) {
                    $('#deleted_' + feature + '_panel').removeClass('hide_panel');
                    $('#' + deleted_table + ' tbody').append( $('#' + feature + '_table_header').clone() );
                }
                $('#' + deleted_table + ' tbody').append(deleted_row);

                return false;
            } else {
                $('#' + status_span).removeClass('success');
                $('#' + status_span).addClass('error');
                $('#' + status_span).html('Error: Could not delete ' + feature + ' ' + feature_name);
            }

            setTimeout(function() {
                $('#' + status_span).empty();
            }, 10000);
        },
        error: function(XMLHttpRequest, textStatus, errorThrown) {
            $('#' + status_span).html('Error in XMLHttpRequest: <a href="' + query + '">' + query + '</a>');
        }
    });
}

// undelete a gene/mutant_class/mutant/allele from the loci/mutant_class/mutant_info/allele table. possible options:
// feature     : 'locus', 'mutant', 'mutant_class', 'allele'
// feature_id  : '1', '2',  etc.
// feature_name: gene_symbol or mutant_symbol or mutant_class_symbol or allele_name
function undelete_feature(feature, feature_id, feature_name) {
    var url = '/cgi-bin/medicago/eucap/eucap.pl?action=undelete_' + feature;
    var params = feature + '_id=' + feature_id;

    if(feature === 'allele') {
       params = params + '&mutant_id=' + $('#mutant_id').val();
    } else if(feature === 'mutant') {
       params = params + '&mutant_class_id=' + $('#mutant_class_id').val();
    }

    var query = url + '&' + params;
    var status_span = feature + "_undelete_status";
    var feature_table =  feature + "_table";
    $('#' + status_span).html('<img src="/medicago/eucap/include/images/loading.gif" />');

    $.ajax({
        url: url,
        data: params,
        success: function(data, textStatus, XMLHttpRequest) {
            if(data === "Reverted!") {
                // close any open edit panel
                if(feature === 'locus' || feature === 'mutant') {
                    close_panel_and_scroll('annotate_' + feature, undefined);
                }

                $('#' + status_span).removeClass('error');
                $('#' + status_span).addClass('success');
                $('#' + status_span).html('Undeleted ' + feature + ' ' + feature_name);

                var undeleted_row = $('img.undelete_' + feature + '_' + feature_id).closest('tr').clone();
                $('img.undelete_' + feature + '_' + feature_id).closest('tr').fadeTo(400, 0, function () {
                    $(this).remove();
                });

                undeleted_row.find('img.undelete_' + feature + '_' + feature_id)
                    .attr('src', '/medicago/eucap/include/images/delete.png')
                    .attr('alt', function(i, val) { return val.replace(/^un/, ''); })
                    .attr('title', function(i, val) { return val.replace(/^un/, ''); })
                    .attr('onclick', function(i, val) { return val.replace(/^un/, ''); })
                    .attr('class', function(i, val) { return val.replace(/^un/, ''); });

                undeleted_row.find('input#annotate_' + feature + '_' + feature_id).prop('disabled', false);
                undeleted_row.find('input#annotate_' + feature + '_members_' + feature_id).prop('disabled', true);

                var num_deleted_rows = $('#deleted_' + feature_table + ' tr').length;
                if(num_deleted_rows === 2) {
                    $('#deleted_' + feature_table + ' tr').remove();
                    $('#deleted_' + feature + '_panel').addClass('hide_panel');
                }
                $('#' + feature_table + ' tbody').append(undeleted_row);

                return false;
            } else {
                $('#' + status_span).removeClass('success');
                $('#' + status_span).addClass('error');
                $('#' + status_span).html('Error: Could not undelete ' + feature + ' ' + feature_name);
            }

            setTimeout(function() {
                $('#' + status_span).empty();
            }, 10000);
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
    req_locus_fields['reference_pub'] = 1;
    var track = 0;
    $.each(params_arr, function(i, params_arr){
        if(req_locus_fields[params_arr.name] === 1 && params_arr.value !== "") {
            track += 1;
        }
    });
    if(track === 2) {
        $('#gene_symbol').removeClass('ui-state-error');
        $('#reference_pub').removeClass('ui-state-error');
        var req_locus_fields = new Array();
        req_locus_fields['gb_genomic_acc'] = 1;
        req_locus_fields['gb_cdna_acc'] = 1;
        req_locus_fields['gb_protein_acc'] = 1;
        $.each(params_arr, function(i, params_arr){
            if(req_locus_fields[params_arr.name] === 1 && params_arr.value !== "") {
                track += 1;
            }
        });

        if(track >= 3) {
            $('#gb_genomic_acc, #gb_cdna_acc, #gb_protein_acc').removeClass('ui-state-error');

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

                            var msg = '';
                            if(data.locus_edits || data.mutant_info_edits || data.mutant_class_edits) {
                                msg = message[0];
                            } else {
                                msg = message[1];
                                if(!data.locus_edits) {
                                    remove_edits_highlight(data.locus_id, 'locus');
                                }
                                if(!data.mutant_info_edits) {
                                    remove_edits_highlight(data.mutant_id, 'mutant');
                                }
                                if(!data.mutant_class_edits) {
                                    remove_edits_highlight(data.mutant_class_id, 'mutant_class');
                                }
                            }

                            $('#' + status_span).html(msg);
                            update_locus_table(locus_id);
                        } else {
                            $('#' + status_span).html('No changes to update.');
                        }

                        setTimeout(function() {
                            $('#' + status_span).empty();
                        }, 10000);

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
            $('#' + status_span).html('Any one of the GenBank Accessions is mandatory! Please fill out these fields.');
            $('#gb_genomic_acc, #gb_cdna_acc, #gb_protein_acc').addClass('ui-state-error');
        }
    } else {
        $('#' + status_span).removeClass('success');
        $('#' + status_span).addClass('ui-state-error');
        $('#' + status_span).html('Gene Symbol and Reference Publication are mandatory! Please fill out these fields.');

        $('#gene_symbol').addClass('ui-state-error');
        $('#reference_pub').addClass('ui-state-error');
    }
    return false;
}

// add/save all the mutant_class edits to database. make sure that mutant_class_symbol
// and mutant_class_name are provided
function mutant_class( action, form_id ) {
    var url = '/cgi-bin/medicago/eucap/eucap.pl?action=' + action;
    var params_arr = $('#' + form_id).serializeArray();
    var status_span = "mutant_save_status";

    var req_mutant_class_fields = new Array();
    req_mutant_class_fields['mutant_class_symbol'] = 1;
    req_mutant_class_fields['mutant_class_name'] = 1;
    var track = 0;
    $.each(params_arr, function(i, params_arr){
        if(req_mutant_class_fields[params_arr.name] === 1 && params_arr.value !== "") {
            track += 1;
        }
    });

    if(track === 2) {
        $('#mutant_class_symbol').removeClass('ui-state-error');
        $('#mutant_class_name').removeClass('ui-state-error');

        var params = $('#' + form_id).serialize();
        var query = url + '&' + params;

        $('#' + status_span).removeClass('ui-state-error');
        $('#' + status_span).addClass('success');
        $('#' + status_span).html('<img src="/medicago/eucap/include/images/loading.gif" />');

        $.ajax({
            type: 'POST',
            url: url,
            data: params,
            success: function(data, textStatus, XMLHttpRequest) {
                if(action === 'add_mutant_class') {
                    $('#' + status_span).html(data);
                    setTimeout(function() {
                        window.location = '/cgi-bin/medicago/eucap/eucap.pl?action=dashboard&mutant_panel=1';
                    }, 500);
                } else if(action === 'save_mutant_class') {
                    if(data.updated === 1) {
                        var msg = '';
                        if(data.mutant_class_edits) {
                            msg = message[0];
                        } else {
                            msg = message[1];
                            if(!data.mutant_class_edits) {
                                remove_edits_highlight(data.mutant_class_id, 'mutant_class');
                            }
                        }

                        $('#' + status_span).html(msg);

                        mutant_class_id = $('#mutant_class_id').val();
                        update_mutant_class_table(mutant_class_id);
                    } else {
                        $('#' + status_span).html('No changes to update.');
                    }

                    setTimeout(function() {
                        $('#' + status_span).empty();
                    }, 10000);
                }
            },
        });
    } else {
         $('#' + status_span).removeClass('success');
         $('#' + status_span).addClass('error');
         $('#' + status_span).html('Mutant Class Symbol and Expansion are mandatory! Please fill out these fields.');

         $('#mutant_class_symbol').addClass('ui-state-error');
         $('#mutant_class_name').addClass('ui-state-error');
    }
    return false;
}

// save all the mutant edits to database. make sure that mutant_symbol,
// phenotype, mutant_class_symbol and class_name are provided
function save_mutant(mutant_id) {
    var url = '/cgi-bin/medicago/eucap/eucap.pl?action=save_mutant';
    if ( $('#mutant_symbol').val() === 'Search mutants...') {
        $('#mutant_symbol').val("");
    }

    var status_span = "mutant_save_status";
    var params_arr = $('#mutant_annotate').serializeArray();

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

    if(track === 5) {
        $('#mutant_symbol').removeClass('ui-state-error');
        $('#mutant_class_symbol').removeClass('ui-state-error');
        $('#mutant_class_name').removeClass('ui-state-error');
        $('#mutant_phenotype').removeClass('ui-state-error');
        $('#mutant_reference_pub').removeClass('ui-state-error');

        var params = $('#mutant_annotate').serialize();
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
                    if(data.updated_mutant === 1) {
                        $('#mutant_mod_date').val(data.mutant_mod_date);
                        $('#mod_date').html('Last Modified date: <b>' + data.mutant_mod_date + '</b>');

                        $('#mutant_id').val(data.mutant_id);

                        var button_label = (data.has_alleles > 0) ? "Edit" : "Add";
                        $('#disp_get_alleles').html(
                            '<input type="button" id="get_alleles" name="get_alleles"'
                            + ' value="' + button_label
                            + '" onclick="perform_action(\'annotate_alleles\', \'mutant_id\', '
                            + data.mutant_id + ')" />'
                        );
                        update_mutant_table(mutant_id);
                    }

                    if(data.updated_mutant_class === 1) {
                        $('mutant_class_id').val(data.mutant_class_id);
                    }

                    var msg = '';
                    if(data.mutant_info_edits || data.mutant_class_edits) {
                        msg = message[0];
                    } else {
                        msg = message[1];
                        if(!data.mutant_info_edits) {
                            remove_edits_highlight(data.mutant_id, 'mutant');
                        }
                        if(!data.mutant_class_edits) {
                            remove_edits_highlight(data.mutant_class_id, 'mutant_class');
                        }
                    }

                    $('#' + status_span).html(msg);
                } else {
                    $('#' + status_span).html('No changes to update.');
                }

                setTimeout(function() {
                    $('#' + status_span).empty();
                }, 10000);

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

            $('#num_alleles_' + mutant_id).html(data.has_alleles);

            setTimeout(function() {
                $('#' + status_span).empty();
            }, 10000);
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

//update the mutant_table {
function update_mutant_table(mutant_id) {
    $('#mutant_symbol_' + mutant_id).html('<em>' + $('#mutant_symbol').val() + '</em>');
    $('#mutant_phenotype_' + mutant_id).html('<em>' + $('#mutant_phenotype').val() + '</em>');
    $('#mapping_data_' + mutant_id).html($('#mapping_data').val());
    $('#reference_lab_' + mutant_id).html($('#mutant_reference_lab').val());
    $('#reference_pub_' + mutant_id).html($('#mutant_reference_pub').val());
}

//update the mutant_class table
function update_mutant_class_table(mutant_class_id) {
    $('#mutant_class_symbol_' + mutant_class_id).html('<em>' + $('#mutant_class_symbol').val() + '</em>');
    $('#mutant_class_name_' + mutant_class_id).html('<em>' + $('#mutant_class_name').val() + '</em>');
}

// remove edits highlighting
function remove_edits_highlight(id, prefix) {
    $('.' + prefix + '_' + id).removeClass('tableRowEdit');
    $('.' + prefix + '_' + id).addClass('tableRowOdd');
}

// perform action: make ajax GET call to eucap.pl with `action`,  parameter `param_name` and `param` as value
// if (`param` === [0-9]+) or (param === ''), make ajax GET call with single paramater `param_name` and its val(),
// else, make ajax POST call by serializing all form input elements
function perform_action(action, param_name, param) {
    if(param_name === undefined && param === undefined) {
        param = action;
        //action = $('#'+ action + '_form input[name=action]').val();
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

    if(action === 'annotate_mutant_class') {
        params = params + '&mutant_class_id=' + $('#mutant_class_id').val();
    }

    var query = url + '&' + params;

    if(action === 'annotate_alleles' || action === 'struct_anno'
            || action === 'review_annotation' || action === 'add_mutant_class_dialog'
            || action === 'annotate_mutant_class' || action === 'view_locus') {
        $('#overlay').show();

        var width = 1000;
        if(action === 'review_annotation') {
            width = 1200;
        } else if(action === 'add_mutant_class_dialog' || action === 'annotate_mutant_class') {
            width = 350;
        }

        $('#' + action).dialog({
            autoOpen: false,
            modal: (action.match(/^view/)) ? false : true,
            width: (action.match(/^view/)) ? 800 : width,
            closeOnEscape: false,
            position: 'left',
        });
    } else {
        var m = (action === 'run_blast') ? 'Searching' : 'Loading';
        $('#' + action).html('<img src="/medicago/eucap/include/images/loading.gif" /><p class="bodytext">' + m + '</p>');
    }

    if(action !== 'submit_struct_anno') {
        goToByScroll(action);
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

            if(action === 'annotate_alleles' || action === 'struct_anno'
                || action === 'review_annotation' || action === 'add_mutant_class_dialog'
                || action === 'annotate_mutant_class' || action === 'view_locus') {
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

// toggle mutant panel based on flag
function toggle_mutant_panel(input_elem_id, flag) {
    var panel_elem = $('#mutant_panel');
    var input_elem = $('#' + input_elem_id);
    if(panel_elem.css('display') === 'block') {
        panel_elem.css('display', 'none');
        if(flag === 0) {
            input_elem.val('Add');
        } else {
            input_elem.val('View/Edit');
        }
    } else {
        panel_elem.css('display', 'block');
        input_elem.val('Hide');
    }
}

// Empty a certain DOM element by id
function clear_element(id) {
    $('#' + id).empty();
}

// close a certain panel on click and scroll page to a specified panel
function close_panel_and_scroll(panel_to_close, panel_to_scroll_to) {
    clear_element(panel_to_close);
    if(panel_to_scroll_to !== undefined) {
        goToByScroll(panel_to_scroll_to);
    }
}

// close a certain dialog
function close_dialog_and_scroll(dialog_to_close, panel_to_scroll_to) {
    $('#' + dialog_to_close).dialog('close');
    if(panel_to_scroll_to !== undefined) {
        goToByScroll(panel_to_scroll_to);
    }
}

// scroll to a certain anchor on the page
function goToByScroll(id){
    $('html,body').animate({scrollTop: $("#"+id).offset().top}, 'slow');
}

// check all checkboxes belonging to a certain div/span id
function check_all( id, checkbox_class ) {
    $("." + checkbox_class).attr('checked', $('#' + id).is(':checked'));
}
