// Runs on DOMContentLoaded so window.stashTagAutocomplete (loaded via tag-autocomplete.js) exists.
document.addEventListener('DOMContentLoaded', function () {
    var list = document.getElementById('cond-list');
    var addBtn = document.getElementById('cond-add');
    var template = document.getElementById('cond-template');
    if (!list || !addBtn || !template) return;
    var knownTags = [];
    try { knownTags = JSON.parse(list.getAttribute('data-known-tags')) || []; } catch (e) {}

    function syncRow(row) {
        var type = row.querySelector('.cond-type').value;
        var text = row.querySelector('.cond-value-text');
        var bool = row.querySelector('.cond-value-bool');
        if (type === 'isArchived' || type === 'hasTags') {
            text.disabled = true; text.style.display = 'none';
            bool.disabled = false; bool.style.display = '';
        } else {
            bool.disabled = true; bool.style.display = 'none';
            text.disabled = false; text.style.display = '';
            text.type = (type === 'createdBefore' || type === 'createdAfter') ? 'date' : 'text';
        }
    }

    function updateRemoveButtons() {
        var rows = list.querySelectorAll('.cond-row');
        rows.forEach(function (row) {
            row.querySelector('.cond-remove').disabled = (rows.length <= 1);
        });
    }

    function wireRow(row) {
        var typeSelect = row.querySelector('.cond-type');
        typeSelect.addEventListener('change', function () { syncRow(row); });
        row.querySelector('.cond-remove').addEventListener('click', function () {
            row.remove();
            updateRemoveButtons();
        });
        if (knownTags.length && window.stashTagAutocomplete) {
            window.stashTagAutocomplete(row.querySelector('.cond-value-text'), knownTags, {
                multi: false,
                enabled: function () { return typeSelect.value === 'tag'; }
            });
        }
        syncRow(row);
    }

    list.querySelectorAll('.cond-row').forEach(wireRow);
    updateRemoveButtons();

    addBtn.addEventListener('click', function () {
        var clone = template.content.firstElementChild.cloneNode(true);
        list.appendChild(clone);
        wireRow(clone);
        updateRemoveButtons();
    });
});
