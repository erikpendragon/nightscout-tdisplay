/*
 * Nightscout T-Display - a standalone Nightscout glucose display
 * Copyright (C) 2026 erikpendragon
 *
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the Free
 * Software Foundation, either version 3 of the License, or (at your option)
 * any later version. See LICENSE, and NOTICE for the ESPHome relationship.
 */
// Two bits of UI behaviour ESPHome's web server has no option for.
//
//  1. While "Use Nightscout Thresholds" is on, the four glucose thresholds are
//     shown read-only: the value still says what the device is using, but the
//     min/max spinner goes so they don't look editable when editing them
//     would achieve nothing.
//  2. "Reservoir life" only means anything when the reservoir is tracked
//     separately from the pod, so it is hidden unless "Separate Reservoir"
//     is on. On Omnipod the reservoir is inside the pod and the setting is
//     noise; on a tubed pump it matters.
//  3. The token field answers its own question. Whether a token is needed is a
//     property of the Nightscout you point at, so the "Token needed?" row is
//     folded into the field itself - "not required" and disabled when reads
//     are open, an editable box when they are not.
//
// Done with an injected stylesheet wherever possible: the v3 UI is lit-based
// and re-renders rows on state updates, which wipes inline styles and
// properties. Rules key off the inputs' stable name attributes and survive.
//
// This reaches into the v3 UI's shadow DOM, which is not a documented API. If
// an ESPHome upgrade restructures it this stops working, and fails quietly.
(function () {
  var SWITCH = 'Use Nightscout Thresholds';
  var RES_SWITCH = 'Separate Reservoir';
  var RES_FIELD = 'Reservoir life (hours)';
  var LOCKED = ['Urgent High', 'High', 'Low', 'Urgent Low'];
  var NEEDED_ROW = 'Token needed?';
  var HIDDEN_ROWS = [];
  var STYLE_ID = 'cgm-ui-style';

  function table() {
    var app = document.querySelector('esp-app');
    if (!app || !app.shadowRoot) return null;
    var t = app.shadowRoot.querySelector('esp-entity-table');
    return (t && t.shadowRoot) ? t.shadowRoot : null;
  }

  // row layout is [spacer, name, control]
  function nameOf(row) {
    return row.children[1] ? row.children[1].textContent.trim() : '';
  }

  function rowNamed(root, n) {
    var rows = root.querySelectorAll('.entity-row');
    for (var i = 0; i < rows.length; i++) if (nameOf(rows[i]) === n) return rows[i];
    return null;
  }

  function switchIsOn(root, name) {
    var row = rowNamed(root, name);
    if (!row) return null;
    var sw = row.querySelector('esp-switch');
    if (!sw || !sw.shadowRoot) return null;
    var box = sw.shadowRoot.querySelector('input[type=checkbox]');
    return box ? box.checked : null;
  }

  function css(lockThresholds, tokenNeeded, separateRes) {
    var out = '';
    if (lockThresholds) {
      var sel = LOCKED.map(function (n) { return 'input[name="number/' + n + '"]'; });
      out += sel.join(',') + '{opacity:.5;pointer-events:none;}';
      out += sel.map(function (s) { return 'div.range:has(> ' + s + ') > label'; })
               .join(',') + '{display:none;}';
    }
    var tok = 'input[name="text/Token"]';
    if (tokenNeeded === false) {
      out += tok + '{display:none;}';
      out += 'div:has(> ' + tok + ')::after{content:"not required";opacity:.45;font-style:italic;}';
    } else if (tokenNeeded === true) {
      out += 'div:has(> ' + tok + ')::after{content:" required";color:#FFD600;font-size:.85em;}';
    }
    // null means the row has not rendered yet - leave it alone rather than
    // flashing the field away and back.
    if (separateRes === false)
      out += '.entity-row:has(input[name="number/' + RES_FIELD + '"])' +
             '{display:none;}';
    return out;
  }

  function apply() {
    var root = table();
    if (!root) return;
    var on = switchIsOn(root, SWITCH);
    if (on === null) return;                          // rows not rendered yet
    var resOn = switchIsOn(root, RES_SWITCH);

    // read the answer, then fold that row away
    var needed = null;
    var nrow = rowNamed(root, NEEDED_ROW);
    if (nrow) {
      var txt = nrow.children[2] ? nrow.children[2].textContent.trim() : '';
      if (/^no\b/i.test(txt)) needed = false;
      else if (/^yes\b/i.test(txt)) needed = true;
      nrow.style.display = 'none';
    }

    HIDDEN_ROWS.forEach(function (n) {
      var r = rowNamed(root, n);
      if (r) r.style.display = 'none';
    });

    var el = root.getElementById ? root.getElementById(STYLE_ID)
                                 : root.querySelector('#' + STYLE_ID);
    var want = css(on, needed, resOn);
    if (!el) {
      el = document.createElement('style');
      el.id = STYLE_ID;
      root.appendChild(el);
    }
    if (el.textContent !== want) el.textContent = want;
  }

  // The switch can also be changed from Home Assistant or another browser.
  setInterval(apply, 800);
  document.addEventListener('click', function () { setTimeout(apply, 150); }, true);
  apply();
})();
