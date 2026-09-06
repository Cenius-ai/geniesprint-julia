/* GenieTeam UI behaviour — vanilla, no remote resources.
   Responsibilities: mobile nav toggle, show/hide password, submit busy-state,
   flash dismissal. All DOM writes use safe APIs only: class/attribute toggles
   and textContent only; no HTML strings are constructed. */
(function () {
  'use strict';

  function ready(fn) {
    if (document.readyState !== 'loading') { fn(); } else { document.addEventListener('DOMContentLoaded', fn); }
  }

  ready(function () {
    var body = document.body;

    /* --- Mobile navigation toggle ------------------------------------ */
    var navToggle = document.querySelector('[data-nav-toggle]');
    var sidebar = document.getElementById('sidebar');
    if (navToggle && sidebar) {
      navToggle.addEventListener('click', function () {
        var open = body.classList.toggle('nav-open');
        navToggle.setAttribute('aria-expanded', open ? 'true' : 'false');
      });
      // Tap anywhere outside the sidebar closes it (desktop unaffected).
      document.addEventListener('click', function (ev) {
        if (!body.classList.contains('nav-open')) { return; }
        if (!sidebar.contains(ev.target) && !navToggle.contains(ev.target)) {
          body.classList.remove('nav-open');
          navToggle.setAttribute('aria-expanded', 'false');
        }
      });
      // Close on Escape.
      document.addEventListener('keydown', function (ev) {
        if (ev.key === 'Escape' && body.classList.contains('nav-open')) {
          body.classList.remove('nav-open');
          navToggle.setAttribute('aria-expanded', 'false');
          navToggle.focus();
        }
      });
    }

    /* --- Show / hide password -----------------------------------------
       Both icons are server-rendered inside the button; we only toggle the
       `hidden` attribute, so no HTML string is ever constructed here. */
    var toggles = document.querySelectorAll('[data-password-toggle]');
    Array.prototype.forEach.call(toggles, function (btn) {
      btn.addEventListener('click', function () {
        var wrap = btn.closest('[data-password]') || btn.closest('.input-affix');
        var input = wrap ? wrap.querySelector('input[type="password"], input[type="text"]') : null;
        if (!input) { return; }
        var show = input.type === 'password';
        input.type = show ? 'text' : 'password';
        btn.setAttribute('aria-label', show ? 'Hide password' : 'Show password');
        btn.setAttribute('aria-pressed', show ? 'true' : 'false');
        var onIcon = btn.querySelector('.pw-ic--show');
        var offIcon = btn.querySelector('.pw-ic--hide');
        if (onIcon) { onIcon.hidden = !show; }
        if (offIcon) { offIcon.hidden = show; }
        input.focus();
      });
    });

    /* --- Submit busy state --------------------------------------------- */
    var forms = document.querySelectorAll('form[data-submit-guard]');
    Array.prototype.forEach.call(forms, function (form) {
      form.addEventListener('submit', function () {
        var submits = form.querySelectorAll('button[type="submit"]');
        Array.prototype.forEach.call(submits, function (btn) {
          if (btn.disabled) { return; }
          btn.disabled = true;
          btn.classList.add('is-loading');
          btn.setAttribute('aria-busy', 'true');
          var label = btn.querySelector('span');
          if (label && !btn.hasAttribute('data-restore-label')) {
            btn.setAttribute('data-restore-label', label.textContent);
            var loading = btn.getAttribute('data-loading-label');
            if (loading) { label.textContent = loading; }
          }
        });
      });
      // Re-enable when the browser refuses submission (client-side required fails).
      form.addEventListener('invalid', function () {
        Array.prototype.forEach.call(form.querySelectorAll('button[type="submit"]'), function (btn) {
          btn.disabled = false;
          btn.classList.remove('is-loading');
          btn.setAttribute('aria-busy', 'false');
          var label = btn.querySelector('span');
          if (label && btn.hasAttribute('data-restore-label')) {
            label.textContent = btn.getAttribute('data-restore-label');
          }
        });
      }, true);
    });

    /* --- Flash dismissal ------------------------------------------------ */
    var flashes = document.querySelectorAll('[data-flash]');
    Array.prototype.forEach.call(flashes, function (flash) {
      var closer = flash.querySelector('[data-flash-close]');
      if (closer) {
        closer.addEventListener('click', function () {
          flash.style.opacity = '0';
          window.setTimeout(function () { flash.remove(); }, 160);
        });
      }
      // Auto-dismiss success/notice flashes after a comfortable pause.
      if (flash.classList.contains('flash--success') || flash.classList.contains('flash--notice')) {
        window.setTimeout(function () {
          if (document.body.contains(flash)) {
            flash.style.transition = 'opacity 220ms ease-out';
            flash.style.opacity = '0';
            window.setTimeout(function () { flash.remove(); }, 240);
          }
        }, 5200);
      }
    });
  });
})();
