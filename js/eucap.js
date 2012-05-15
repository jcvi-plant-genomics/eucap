/* Functions used for structural annotation */
function displayCoords(abs_end5, abs_end3, rel_end5, rel_end3) {
    $('#subfeature_coords input[id=rel_end5]').val(rel_end5);
    $('#subfeature_coords input[id=rel_end3]').val(rel_end3);
    $('#subfeature_coords input[id=abs_end5]').val(abs_end5);
    $('#subfeature_coords input[id=abs_end3]').val(abs_end3);
    return true;
}

function setCursor() {
    var caimg = $('#ca_image');
    caimg.css('cursor', 'pointer');
    return true;
}

function restoreCursor() {
    var caimg = $('#ca_image');
    caimg.css('cursor', 'default');
    return true;
}

function deleteFeature(input_elem) {
    var row = input_elem.parentNode.parentNode.parentNode;
    var row_index = row.sectionRowIndex;
    var ca_tbody = document.getElementById('ca_table_body');
    ca_tbody.deleteRow(row_index + 1);
    ca_tbody.deleteRow(row_index);
    return;
}

function addFeature(input_elem) {
    var add_feature_row_html = '<td colspan="5" align="right"><p><input type="button" name="add_feature" value="Add Feature" onclick="addFeature(this)"></p></td>';
    var feature_row_html = '<td><p><input type="button" name="delete" value="Delete" onclick="deleteFeature(this)"></p></td>' +
        '<td><p><select name="type"><option value="CDS">CDS</option><option value="UTR">UTR</option></select></p></td>' +
        '<td><p><input type="text" id="start" name="start" size="10" value="end5" onfocus="if(this.value == \'end5\') this.value = \'\';" onblur="if(this.value == \'\') this.value = \'end5\';"></p></td>' +
        '<td><p><input type="text" id="stop" name="stop" size="10" value="end3" onfocus="if(this.value == \'end3\') this.value = \'\';" onblur="if(this.value == \'\') this.value = \'end3\';">' +
        '</p></td><td><p>&nbsp;</p></td>';
    var row = input_elem.parentNode.parentNode.parentNode;
    var row_index = row.sectionRowIndex;
    var ca_tbody = document.getElementById('ca_table_body');
    ca_tbody.insertRow(row_index);
    ca_tbody.insertRow(row_index);
    ca_tbody.rows[row_index].innerHTML = add_feature_row_html;
    ca_tbody.rows[row_index].className = 'add tableRowOdd';
    ca_tbody.rows[row_index+1].innerHTML =  feature_row_html;
    ca_tbody.rows[row_index+1].className = 'feature';
    return;
}

function is_all_ws( nod )
{
  // Use ECMA-262 Edition 3 String and RegExp features
  return !(/[^\t\n\r ]/.test(nod.data));
}

function is_ignorable( nod )
{
  return ( nod.nodeType == 8) || // A comment node
    ( (nod.nodeType == 3) && is_all_ws(nod) ); // a text node, all ws
}

function first_child( par )
{
  var res=par.firstChild.firstChild;
  while (res) {
    if (!is_ignorable(res)) return res;
    res = res.nextSibling;
  }
  return null;
}

function validateCaModel( ca_model_json ) {
    var strand = ca_model_json.strand;
    var subfeats = ca_model_json.subfeatures;
    for ( var i = 0; i < subfeats.length; i++){
        /* conditions to check for:
           start with a CDS - only one seen UTR - fail on seeing CDS again
           start with UTR
        */
    }
    return true;
}

function adjustModelSpan() {
    var ca_tbody = document.getElementById('ca_table_body');
    var rows = ca_tbody.getElementsByTagName('tr');
    var strand = document.struct_anno_form.locus_strand.value;
    var model_start = document.struct_anno_form.locus_start.value;
    var model_stop = document.struct_anno_form.locus_stop.value;

    //get the first and last feature rows
    var first_feature_row = rows[1];
    var last_feature_row = rows[rows.length - 2];

    var input_start = first_child(first_feature_row.cells[2]);
    var input_stop = first_child(last_feature_row.cells[3]);
    if ( strand == 1 ){
        document.struct_anno_form.locus_start.value = input_start.value < model_start ? input_start.value : model_start;
        document.struct_anno_form.locus_stop.value = input_stop.value  > model_stop ? input_stop.value : model_stop;
    }
    else{
        document.struct_anno_form.locus_start.value = input_start.value > model_start ? input_start.value : model_start;
        document.struct_anno_form.locus_stop.value = input_stop.value  <  model_stop ? input_stop.value : model_stop;
    }
    return;
}

function createSubFeatJSON() {
    var ca_model = {};
    //set the max min coords at this point
    adjustModelSpan();
    ca_model.type = document.struct_anno_form.locus_type.value;
    ca_model.seq_id = document.struct_anno_form.locus_seq_id.value;
    ca_model.start = document.struct_anno_form.locus_start.value;
    ca_model.stop = document.struct_anno_form.locus_stop.value;
    ca_model.strand = document.struct_anno_form.locus_strand.value;
    var ca_model_subfeats = [];
    var ca_tbody = document.getElementById('ca_table_body');
    //var rows = ca_tbody.getElementsByTagName('tr');
    var rows = ca_tbody.rows;
    for ( var i = 0; i < rows.length; i++ ){
        if ( rows[i].className != "feature" ){
            continue;
        }

        var feature = {};
        var td_elems = rows[i].cells;

        //fetch type
        var feature_select = first_child(td_elems[1]);
        var input_start = first_child(td_elems[2]);
        var input_stop =  first_child(td_elems[3]);

        feature.type = feature_select.value;
        feature.start = input_start.value;
        feature.stop = input_stop.value;
        ca_model_subfeats.push(feature);
    }
    ca_model.subfeatures = ca_model_subfeats;
    var ca_model_json = JSON.stringify(ca_model);
    //var result = validateCaModel( ca_model_json );
    var result = true;
    if ( result == false ){
        return false;
    }
    else{
        return ca_model_json;
    }
}

function update_model_json(action) {
    if(action === 'struct_anno') {
        var ca_model_json = createSubFeatJSON();
        $('#model_json').val(ca_model_json);
    }
    $('#struct_anno_form input[id=action]').val(action);
    //$('#action').val('struct_anno');
    return true;
}

/* Annotation Template JS */
function set_action(elem) {
    var hidden = $('#action');
    if (elem.val() === 'Update Profile'){
        hidden.val('update_profile');
    } else if(elem.val() === 'Sign Up') {
        hidden.val('signup_user');
    }
}

// set value of DOM element by element_id and form_id
function set_value(id, value, form_id) {
    if(form_id === undefined) {
        $('#' + id).val(value);
    } else {
        $('#' + form_id + ' input').filter('[id=' + id + ']').val(value);
    }
}

//// prettify all the buttons
$(function() {
    $('.submitButton, .inputButton, .resetButton').button();
});
