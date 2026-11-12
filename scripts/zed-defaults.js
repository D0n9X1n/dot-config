// Zed opens text and code files by default (macOS).
//
// osascript -l JavaScript scripts/zed-defaults.js <bundle id> <check|apply> <uti>...
//
// check prints one "<uti> <handler>" line per type and exits 0. apply asks Launch
// Services to make the bundle the handler only for types it does not already handle;
// macOS then shows one "Use <app>?" dialog per changed type, and the person decides.
// Nothing is retried. Types the system does not know (dyn.* ids) are skipped.
ObjC.import('CoreServices');

function handler(uti) {
  return ObjC.unwrap(ObjC.castRefToObject($.LSCopyDefaultRoleHandlerForContentType($(uti), $.kLSRolesAll))) || '';
}

function run(argv) {
  const [bundle, mode, ...utis] = argv;
  if (!bundle || (mode !== 'check' && mode !== 'apply')) {
    throw new Error('usage: zed-defaults.js <bundle id> <check|apply> <uti>...');
  }
  const out = [];
  for (const uti of utis) {
    if (uti.startsWith('dyn.')) continue;
    const now = handler(uti);
    if (mode === 'check') {
      out.push(uti + ' ' + (now || '-'));
    } else if (now.toLowerCase() !== bundle.toLowerCase()) {
      $.LSSetDefaultRoleHandlerForContentType($(uti), $.kLSRolesAll, $(bundle));
      out.push(uti + ' asked (was ' + (now || 'none') + ')');
    }
  }
  return out.join('\n');
}
