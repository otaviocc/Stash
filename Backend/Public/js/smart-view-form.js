// Runs on DOMContentLoaded so window.stashTagAutocomplete (loaded via tag-autocomplete.js) exists.
document.addEventListener('DOMContentLoaded', function () {
    var list = document.getElementById('cond-list');
    var addBtn = document.getElementById('cond-add');
    var template = document.getElementById('cond-template');
    if (!list || !addBtn || !template) return;
    var knownTags = [];
    try { knownTags = JSON.parse(list.getAttribute('data-known-tags')) || []; } catch (e) {}

    function assembleDuration(row) {
        var text = row.querySelector('.cond-value-text');
        var num = row.querySelector('.cond-duration-num');
        var unit = row.querySelector('.cond-duration-unit');
        var amount = parseInt(num.value, 10);
        if (isNaN(amount) || amount < 1) { amount = 1; num.value = '1'; }
        text.value = amount + unit.value;
    }

    function syncRow(row) {
        var type = row.querySelector('.cond-type').value;
        var text = row.querySelector('.cond-value-text');
        var bool = row.querySelector('.cond-value-bool');
        var duration = row.querySelector('.cond-value-duration');
        var isBool = (type === 'isArchived' || type === 'hasTags' || type === 'isWaybackArchived' || type === 'isReadLater');
        var isDuration = (type === 'olderThan' || type === 'newerThan');
        bool.disabled = !isBool; bool.style.display = isBool ? '' : 'none';
        duration.style.display = isDuration ? '' : 'none';
        if (isBool) {
            text.disabled = true; text.style.display = 'none';
        } else if (isDuration) {
            text.disabled = false; text.style.display = 'none';
            text.type = 'hidden';
            assembleDuration(row);
        } else {
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
        typeSelect.addEventListener('change', function () {
            row.querySelector('.cond-value-text').value = '';
            syncRow(row);
        });
        var num = row.querySelector('.cond-duration-num');
        var unit = row.querySelector('.cond-duration-unit');
        if (num) num.addEventListener('input', function () { assembleDuration(row); });
        if (unit) unit.addEventListener('change', function () { assembleDuration(row); });
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
