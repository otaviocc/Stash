(function () {
    var reveal = document.getElementById('reveal-delete-all');
    var form = document.getElementById('delete-all-form');
    var input = document.getElementById('delete-all-input');
    var submit = document.getElementById('delete-all-submit');
    if (!reveal || !form || !input || !submit) return;
    reveal.addEventListener('click', function () {
        form.style.display = 'block';
        reveal.style.display = 'none';
        input.focus();
    });
    input.addEventListener('input', function () {
        submit.disabled = input.value.trim().toLowerCase() !== 'delete all';
    });
})();
