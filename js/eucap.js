/* $Id: eucap.js 538 2007-07-24 00:19:51Z hamilton $ */

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
    var row = input_elem.parentNode.parentNode;
    var row_index = row.sectionRowIndex;
    var ca_tbody = document.getElementById('ca_table_body');
    ca_tbody.deleteRow(row_index + 1);
    ca_tbody.deleteRow(row_index);
    return;
}
function addFeature(input_elem) {
    var add_feature_row_html = '<td colspan="4" align="right"><input type="button" name="add_feature" value="Add Feature" onclick="addFeature(this)"></td>';
    var feature_row_html = '<td><input type="button" name="delete" value="Delete" onclick="deleteFeature(this)"></td><td><select name="type"><option value="CDS">CDS</option><option value="UTR">UTR</option></select></td> <td><input type="text" name="start" size="10" value="start"></td> <td><input type="text" name="stop" size="10" value="stop"></td>';
    var row = input_elem.parentNode.parentNode;
    var row_index = row.sectionRowIndex;
    var ca_tbody = document.getElementById('ca_table_body');
    ca_tbody.insertRow(row_index);
    ca_tbody.insertRow(row_index);
    ca_tbody.rows[row_index].innerHTML = add_feature_row_html;
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
    var res=par.firstChild;
    while (res) {
        if (!is_ignorable(res)) return res;
        res = res.nextSibling;
    }
    return null;
}

function validateCaModel( ca_model_json) {
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
    var rows = ca_tbody.rows;
    var strand = document.struct_anno.locus_strand.value;
    var model_start = document.struct_anno.locus_start.value;
    var model_stop = document.struct_anno.locus_stop.value;
    //get the first and last feature rows
    var first_feature_row = rows[1];
    var last_feature_row = rows[rows.length - 2];
    var input_start = first_child(first_feature_row.cells[2]);
    var input_stop = first_child(last_feature_row.cells[3]);
    if ( strand == 1 ){
        document.struct_anno.locus_start.value = input_start.value < model_start ? input_start.value : model_start;
        document.struct_anno.locus_stop.value = input_stop.value  > model_stop ? input_stop.value : model_stop;
    }
    else{
        document.struct_anno.locus_start.value = input_start.value > model_start ? input_start.value : model_start;
        document.struct_anno.locus_stop.value = input_stop.value  <  model_stop ? input_stop.value : model_stop;
    }
    return;
}

function createSubFeatJSON() {
    var ca_model = {};
    //set the max min coords at this point
    adjustModelSpan();
    ca_model.type = document.struct_anno.locus_type.value;
    ca_model.seq_id = document.struct_anno.locus_seq_id.value;
    ca_model.start = document.struct_anno.locus_start.value;
    ca_model.stop = document.struct_anno.locus_stop.value;
    ca_model.strand = document.struct_anno.locus_strand.value;
    var ca_model_subfeats = [];
    var ca_tbody = document.getElementById('ca_table_body');
    var rows = ca_tbody.rows;
    for ( var i = 0; i < rows.length; i++ ){
        if ( rows[i].className != "feature" ){
            continue;
        }
        var feature = {};
        var td_elems = rows[i].cells;
        //fetch_type
        var feature_select = first_child(td_elems[1]);
        var input_start = first_child(td_elems[2]);
        var input_stop =  first_child(td_elems[3]);
        feature.type = feature_select.value;
        feature.start = input_start.value;
        feature.stop = input_stop.value;
        ca_model_subfeats.push(feature);
    }
    ca_model.subfeatures = ca_model_subfeats;
    var ca_model_json = ca_model.toJSONString(); 
    //var result = validateCaModel( ca_model_json );
    var result = true;
    if ( result == false ){
        return false;
    }
    else{
        return ca_model_json;
    }
}

function viewAnnotation() {
    var ca_model_json =  createSubFeatJSON();
    var model_json_elem = document.getElementById('model_json');
    model_json_elem.value = ca_model_json;
    //submit form with view action
    document.struct_anno.submit();
}

function submitAnnotation() {
    var ca_model_json =  createSubFeatJSON();
    var model_json_elem = document.getElementById('model_json');
    model_json_elem.value = ca_model_json;
    var input_action = document.getElementById('action');
    input_action.value = 'submit_struct_anno';
    document.struct_anno.submit();
    return true;
}

/* Annotation Template JS */
function set_action(elem, locus) {
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
    else if (elem.value == "Save Functional Annotation to Database" ){
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
        var hidden_locus = document.getElementById('locus');
        hidden_locus.value = locus;
    }
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
function remove_blast_div() {
    var blast_div = document.getElementById('blast_results');
    blast_div.innerHTML = '';
    return;
}
function select_all_blast_hits(){
    var add_checkbox_array = document.annotate.add;
    for (var i = 0; i < add_checkbox_array.length; i++){
        add_checkbox_array[i].checked = true;
    }
    return;
}
function clear_all_blast_hits(){
    var add_checkbox_array = document.annotate.add;
    for (var i = 0; i < add_checkbox_array.length; i++){
        add_checkbox_array[i].checked = false;
    }
    return;
}     
function hide_panel(input_elem) {
    var panel_elem = document.getElementById('add_panel');
    if ( panel_elem.style.display == 'block'){
        panel_elem.style.display = 'none';
        input_elem.value = 'Show Add Gene Family Panel';
    }
    else{
        panel_elem.style.display = 'block';
        input_elem.value = 'Hide Add Gene Family Panel';
    }
}