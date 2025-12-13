/** @type {import('next').NextConfig} */
const nextConfig = {
  // Увеличиваем лимит размера тела для Server Actions
  // По умолчанию Next.js ограничивает до 1MB, но для загрузки PDF файлов нужно больше
  // Устанавливаем 50MB (соответствует максимальному размеру файла в uploadSourceAction)
  // В Next.js 16 serverActions находится в experimental
  experimental: {
    serverActions: {
      bodySizeLimit: '50mb',
    },
  },
}

export default nextConfig
