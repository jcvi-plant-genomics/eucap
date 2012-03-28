/* Functions used for structural annotation */
function displayCoords(abs_end5,abs_end3,rel_end5, rel_end3) {
    document.subfeature_coords.rel_end5.value = rel_end5;
    document.subfeature_coords.rel_end3.value = rel_end3;
    document.subfeature_coords.abs_end5.value = abs_end5;
    document.subfeature_coords.abs_end3.value = abs_end3;
    return true;
}

function setCursor() {
    var caimg = document.getElementById('ca_image');
    caimg.style.cursor = "pointer";
    return true;
}

function restoreCursor() {
    var caimg = document.getElementById('ca_image');
    caimg.style.cursor = "default";
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
    var feature_row_html = '<td><p><input type="button" name="delete" value="Delete" onclick="deleteFeature(this)"></p></td> <td><p><select name="type"><option value="CDS">CDS</option><option value="UTR">UTR</option></select></p></td> <td><p><input type="text" name="start" size="10" value="start"></p></td> <td><p><input type="text" name="stop" size="10" value="stop"></p></td><td><p>&nbsp;</p></td>';
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
        document.getElementById('model_json').value = ca_model_json;
    }
    $('#struct_anno_form input[name=action]').val(action);
    //document.getElementById('action').value = 'struct_anno';
    return true;
}

/* Annotation Template JS */
function set_action(elem, locus_id) {
    var hidden = document.getElementById('action');
    if (elem.value == "Add Loci"){
        hidden.value = "add_loci";
    }
    else if (elem.value == "Find Homologs"){
        hidden.value = "run_blast";
    }
    else if (elem.value == "Delete Checked"){
        hidden.value = "delete_checked";
    }
    else if (elem.value == "Save Checked" ){
        hidden.value = "save_annotation";
    }
    else if (elem.value == "Review All Annotation") {
        hidden.value = "review_annotation";
    }
    else if (elem.value == "Submit Annotation") {
        hidden.value = "submit_annotation";
    }
    else if (elem.value == "Go"){
        hidden.value = "struct_anno";
    }
    else if (elem.value == "Update Profile"){
        hidden.value = "update_profile";
    } else if(elem.value == "Add" || elem.value == "Edit"){
        hidden.value = "edit_alleles";
    }

    if( typeof(locus_id) !== 'undefined' ){
        var hidden_locus = document.getElementById('locus_id');
        hidden_locus.value = locus_id;
    }
}

function set_user_and_family(user_id, family_id) {
    $('#user_id').val(user_id);
    $('#family_id').val(family_id);
}

function clear_textarea( textarea_id ){
    var textarea =  document.getElementById( textarea_id );
    textarea.value='';
    return true;
}

function add_blast_loci() {
    var locus_box = document.getElementById('locus_list');
    var temp = locus_box.value;
    var  selected_loci_array = new Array();
    if ( document.annotate.add.length > 0 ){
        for (var i = 0; i < document.annotate.add.length; i++){
            if ( document.annotate.add[i].checked == true ){
                selected_loci_array.push(document.annotate.add[i].value)
            }
        }
        if (selected_loci_array.length == 0){return;}

        var new_loci = '';
        if (selected_loci_array.length == 1){
            new_loci = selected_loci_array[0];
        }
        else{
            new_loci = selected_loci_array.join("\n");
        }
        locus_box.value = temp+new_loci+"\n";
        return;
    }
    else{

        if ( document.annotate.add.checked == true){
            locus_box.value = temp+document.annotate.add.value+"\n";
        }
    }
}

function hide_panel(input_elem, object) {
    var panel_elem = document.getElementById('add_panel');
    if ( panel_elem.style.display == 'block'){
        panel_elem.style.display = 'none';
        input_elem.value = 'Show Add ' + object + ' Panel';
    }
    else{
        panel_elem.style.display = 'block';
        input_elem.value = 'Hide Add ' + object + ' Panel';
    }
}

function toggle_mutant_panel(input_elem, flag) {
    var panel_elem = document.getElementById('mutant_panel');
    if ( panel_elem.style.display == 'block'){
        panel_elem.style.display = 'none';
        if(flag == 0){
            input_elem.value = 'Add';
        }
        else{
            input_elem.value = 'View/Edit';
        }
    }
    else{
        panel_elem.style.display = 'block';
        input_elem.value = 'Hide';
    }

}

/* Select/Unselect check boxes */
function set_checkbox(elem){
    if(elem.value == "Select All") {
        checkAll(document.annotate.toProcess);
    }
    else if(elem.value == "Unselect All") {
        uncheckAll(document.annotate.toProcess);
    }
    else if(elem.value == "Select All Blast Hits") {
        checkAll(document.blastForm.add);
    }
    else if(elem.value = "Clear Selected Blast Hits") {
        uncheckAll(document.blastForm.add);
    }
}

function checkAll(elem)
{
    for (i = 0; i < elem.length; i++)
        elem[i].checked = true;
}

function uncheckAll(elem)
{
    for (i = 0; i < elem.length; i++)
        elem[i].checked = false;
}
