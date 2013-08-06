// function to markup the PMIDs in the publications input box
function markup_pmids(feature) {
    var feature_name = 'reference_pub_tagsinput';
    if(feature !== undefined) {
        feature_name = 'mutant_' + feature_name;
    }
    $('#' + feature_name).find('span.tag').find('span').each(function() {
        var pmid = $(this).html().match(/^PMID:(\d+)/);
        if(pmid) {
            $(this).parent().qtip({
                content: {
                    text: '<img src="/eucap/include/images/loading.gif" />',
                    ajax: {
                        url: '/cgi-bin/eucap/eucap.pl?action=retrieve_pmid_record&term=' + pmid[1],
                        type: 'GET',
                        data: {},
                        dataType: 'json',
                        success: function(data, status) {
                            var tt_content = "";
                            if(data.error !== undefined) {
                                tt_content = data.error;
                            } else {
                                tt_content = data.author + '.&nbsp;(' + data.year + ').&nbsp;'
                                                + '<b>' + data.title + '</b>&nbsp;'
                                                + '<a href="' + data.locator + '" target="_blank">'
                                                + '<i>' + data.journal + '</i>,&nbsp;'
                                                + data.citation + '</a>';
                            }
                            this.set('content.text', tt_content);
                        }
                    }
                },
                position: { my: 'bottom left', at: 'top center' },
                hide: {
                    fixed: true,
                    delay: 500,
                },
                style: 'wiki',
            });
        }
    });
}
