// Press "/" anywhere outside a text field to jump focus into the search box.
document.addEventListener('keydown', function (e) {
    if (e.key !== '/') return;
    var el = document.activeElement;
    if (el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.isContentEditable)) return;
    var search = document.querySelector('input[type="search"]');
    if (!search) return;
    e.preventDefault();
    search.focus();
    search.select();
});
