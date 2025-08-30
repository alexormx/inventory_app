module.exports = {
  ci: {
    collect: {
      url: [
        'http://127.0.0.1:4000/',
        'http://127.0.0.1:4000/catalog',
        // Página show de producto (ajusta el slug / id real en CI con variable de entorno LH_PRODUCT_PATH)
        process.env.LH_PRODUCT_PATH || 'http://127.0.0.1:4000/products/1'
      ],
      numberOfRuns: 1,
      headless: true,
      startServerCommand: 'RAILS_ENV=production bundle exec rails server -p 4000'
    },
    assert: {
      assertions: {
  'categories:performance': ['error', { minScore: 0.85 }],
        'categories:accessibility': ['warn', { minScore: 0.90 }],
        'categories:seo': ['warn', { minScore: 0.90 }],
        'uses-responsive-images': 'off' // ya controlamos manualmente
      }
    },
    upload: {
      target: 'filesystem',
      outputDir: 'lighthouse-report'
    }
  }
};
