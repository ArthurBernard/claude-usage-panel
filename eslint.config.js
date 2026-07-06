// Flat ESLint config for the GNOME Shell (GJS) JavaScript.
// GJS is ESM with a few global helpers; module resolution (gi://, resource://)
// is provided by the Shell at runtime, so we don't resolve imports here.

export default [
    {
        files: ['**/*.js'],
        ignores: ['eslint.config.js'],
        languageOptions: {
            ecmaVersion: 'latest',
            sourceType: 'module',
            globals: {
                console: 'readonly',
                TextEncoder: 'readonly',
                TextDecoder: 'readonly',
                globalThis: 'readonly',
                imports: 'readonly',
                log: 'readonly',
                logError: 'readonly',
                Promise: 'readonly',
                Set: 'readonly',
                Map: 'readonly',
            },
        },
        rules: {
            'no-unused-vars': ['error', {argsIgnorePattern: '^_'}],
            'no-undef': 'error',
            'prefer-const': 'error',
            'no-var': 'error',
            eqeqeq: ['error', 'smart'],
            semi: ['error', 'always'],
        },
    },
];
