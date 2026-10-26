// 构建边界：在 Windows 执行 Swift 语法解析和项目资源一致性检查。
// 输入：源码与配置；输出：JSON 报告；不是 Swift 类型检查或 iOS 编译。
// 依赖：开发目录 .tools 下 ast-grep 与 Swift 语法，不进入应用。
const fs = require('node:fs');
const path = require('node:path');
const base = path.resolve(__dirname, '..');
const { registerDynamicLanguage, parse } = require(path.join(base, '.tools/node_modules/@ast-grep/napi'));
const swift = require(path.join(base, '.tools/node_modules/@ast-grep/lang-swift'));
const bash = require(path.join(base, '.tools/node_modules/@ast-grep/lang-bash'));
const yaml = require(path.join(base, '.tools/node_modules/yaml'));
registerDynamicLanguage({ swift, bash });
const files = [];
function visit(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) visit(full);
    else if (full.endsWith('.swift')) files.push(full);
  }
}
visit(path.join(base, '应用'));
visit(path.join(base, '测试'));
files.push(path.join(base, 'Package.swift'));
const errors = [];
const largeFiles = [];
for (const file of files) {
  const source = fs.readFileSync(file, 'utf8');
  for (const node of parse('swift', source).root().findAll({ rule: { kind: 'ERROR' } })) {
    errors.push({ file: path.relative(base, file), line: node.range().start.line + 1, text: node.text().slice(0, 120) });
  }
  if (source.split('\n').length > 200) largeFiles.push(path.relative(base, file));
}
for (const file of ['构建/准备工程.sh', '构建/验证工程.sh', '构建/打包个人版.sh']) {
  for (const node of parse('bash', fs.readFileSync(path.join(base, file), 'utf8')).root().findAll({rule:{kind:'ERROR'}})) {
    errors.push({file, line:node.range().start.line + 1, text:node.text().slice(0,120)});
  }
}
const project = yaml.parse(fs.readFileSync(path.join(base, 'project.yml'), 'utf8'));
const ci = yaml.parse(fs.readFileSync(path.join(base, 'codemagic.yaml'), 'utf8'));
if (!project.targets.OhRight || !project.schemes.OhRight || !project.configs.PersonalTrial) throw Error('Project configuration missing');
for (const workflow of Object.values(ci.workflows)) {
  if (workflow.environment.xcode !== '26.0' || workflow.publishing || workflow.integrations) throw Error('Unexpected CI capabilities');
  for (const step of workflow.scripts) {
    const invocation = /^bash\s+(\S+)(?:\s+--settings-ui-only)?$/.exec(step.script.trim());
    if (!invocation || !fs.existsSync(path.join(base, invocation[1]))) throw Error('Missing CI script or unsupported invocation');
  }
}
if (ci.workflows['package-personal'].scripts.some(step => step.script.includes('--settings-ui-only'))) {
  throw Error('Personal package must run full verification');
}
for (const file of ['资源/Assets.xcassets/Contents.json', '资源/Assets.xcassets/AppIcon.appiconset/Contents.json']) {
  JSON.parse(fs.readFileSync(path.join(base, file), 'utf8'));
}
if (!fs.existsSync(path.join(base, '资源/Assets.xcassets/AppIcon.appiconset/AppIcon.png'))) {
  errors.push({ file: 'AppIcon.png', text: 'Missing icon' });
}
const report = { checkedAt: new Date().toISOString(), swiftFiles: files.length,
  syntaxErrors: errors, bashScripts: 3, yamlChecks: 'passed', filesOver200Lines: largeFiles,
  limitations: ['Grammar parsing only; Swift type checking, unit execution and iOS build require the macOS workflow.'] };
fs.mkdirSync(path.join(base, 'build'), { recursive: true });
fs.writeFileSync(path.join(base, 'build/static-check.json'), JSON.stringify(report, null, 2));
process.stdout.write(JSON.stringify(report, null, 2) + '\n');
if (errors.length) process.exitCode = 1;
