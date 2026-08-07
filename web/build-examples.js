#!/usr/bin/env node

/**
 * Build script to extract Stellogen examples from /examples directory
 * and generate a JavaScript file for the web playground.
 */

const fs = require('fs');
const path = require('path');

// Configuration: map example keys to their source files
// Order: hello, macros, circuits, lambda, relational examples,
// states examples, proofnets examples
const EXAMPLE_MAPPING = {
  hello: 'hello.sg',
  macros: 'macros.sg',
  circuits: 'circuits.sg',
  // Lambda examples
  'lambda-linear': 'lambda/linear_lambda.sg',
  // Relational examples
  'relational-arithmetic': 'relational/arithmetic.sg',
  'relational-joins': 'relational/joins.sg',
  // States examples
  'states-nfa': 'states/nfa.sg',
  'states-npda': 'states/npda.sg',
  'states-turing': 'states/turing.sg',
  // Proofnets examples
  'proofnets-mll': 'proofnets/mll.sg'
};

// Path configuration
const EXAMPLES_DIR = path.join(__dirname, '..', 'examples');
const OUTPUT_FILE = path.join(__dirname, 'examples.js');
const PRELUDE_FILE = path.join(EXAMPLES_DIR, 'milkyway', 'prelude.sg');

/**
 * Load and prepare prelude content for inlining
 */
function loadPrelude() {
  try {
    const preludeContent = fs.readFileSync(PRELUDE_FILE, 'utf-8');
    return `; Prelude macros (normally imported)\n${preludeContent.trim()}`;
  } catch (error) {
    console.error('❌ Error loading prelude:', error.message);
    process.exit(1);
  }
}

/**
 * Process example file content for the playground
 * - Replace (use "milkyway/prelude.sg") with inline prelude definitions,
 *   since the browser build has no filesystem to resolve imports from.
 * - Adjust any other syntax needed for standalone execution
 */
function processExampleContent(content, _filename, preludeMacros) {
  // For files that import the prelude, inline it.
  // Handle both direct and relative paths to prelude.
  if (content.includes('(use "milkyway/prelude.sg")')) {
    content = content.replace('(use "milkyway/prelude.sg")', preludeMacros);
  }
  if (content.includes('(use "../milkyway/prelude.sg")')) {
    content = content.replace('(use "../milkyway/prelude.sg")', preludeMacros);
  }

  return content.trim();
}

/**
 * Main build function
 */
function buildExamples() {
  console.log('Building examples for Stellogen playground...\n');

  // Load prelude once
  const preludeMacros = loadPrelude();
  console.log('✓ Loaded prelude macros\n');

  const examples = {};
  let successCount = 0;
  let errorCount = 0;

  // Process each example in the mapping
  for (const [key, filename] of Object.entries(EXAMPLE_MAPPING)) {
    const filepath = path.join(EXAMPLES_DIR, filename);

    try {
      if (!fs.existsSync(filepath)) {
        console.error(`❌ File not found: ${filename}`);
        errorCount++;
        continue;
      }

      const content = fs.readFileSync(filepath, 'utf-8');
      const processed = processExampleContent(content, filename, preludeMacros);
      examples[key] = processed;

      console.log(`✓ Processed: ${filename} -> ${key}`);
      successCount++;
    } catch (error) {
      console.error(`❌ Error processing ${filename}:`, error.message);
      errorCount++;
    }
  }

  // Generate the JavaScript file
  const output = `// Auto-generated file - DO NOT EDIT
// Generated from examples/*.sg files
// Run './web/build.sh' or 'node web/build-examples.js' to regenerate

const examples = ${JSON.stringify(examples, null, 2)};

// Export for use in playground
if (typeof module !== 'undefined' && module.exports) {
  module.exports = examples;
}
`;

  fs.writeFileSync(OUTPUT_FILE, output, 'utf-8');

  console.log(`\n✓ Generated: ${OUTPUT_FILE}`);
  console.log(`\nSummary: ${successCount} successful, ${errorCount} errors`);

  if (errorCount > 0) {
    process.exit(1);
  }
}

// Run the build
buildExamples();
