module.exports = {
  ci: {
    collect: {
      url: [
        'http://127.0.0.1:4000/',
        'http://127.0.0.1:4000/catalog',
        // Página show de producto (AJUSTAR LH_PRODUCT_PATH a ruta absoluta o relativa)
        process.env.LH_PRODUCT_PATH?.startsWith('http')
          ? process.env.LH_PRODUCT_PATH
          : `http://127.0.0.1:4000${process.env.LH_PRODUCT_PATH || '/products/1'}`
      ],
      numberOfRuns: 1,
      headless: true,
      startServerCommand: 'RAILS_ENV=production bundle exec rails server -p 4000',
      budgetsFile: 'lighthouse-budgets.json'
    },
    assert: {
      assertions: {
  'categories:performance': ['error', { minScore: 0.85 }],
        'categories:accessibility': ['warn', { minScore: 0.90 }],
        'categories:seo': ['warn', { minScore: 0.90 }],
        // Métricas core
        'largest-contentful-paint': ['error', { maxNumericValue: 2500 }],   // ms
        'cumulative-layout-shift': ['error', { maxNumericValue: 0.1 }],
        // Peso total (warning si excede)
        'total-byte-weight': ['warn', { maxNumericValue: 550000 }],
        // Ya controlado manualmente por nuestros helpers
        'uses-responsive-images': 'off'
      }
    },
    upload: {
      target: 'filesystem',
      outputDir: 'lighthouse-report'
    }
  }
};
