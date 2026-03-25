// Reveal/hide the inline rename form per tag row. Delete uses a native confirm dialog on
// submit (same pattern as deleting a bookmark), so it never mutates the table in place.
document.querySelectorAll('.tag-row').forEach(function (row) {
    var actions = row.querySelector('.tag-actions');
    var renameForm = row.querySelector('.tag-rename-form');
    var input = renameForm.querySelector('input[name="to"]');
    function reset() {
        renameForm.style.display = 'none';
        actions.style.display = '';
    }
    row.querySelector('.rename-toggle').addEventListener('click', function (event) {
        event.preventDefault();
        actions.style.display = 'none';
        renameForm.style.display = 'flex';
        input.focus();
        input.select();
    });
    row.querySelector('.rename-cancel').addEventListener('click', reset);
});
