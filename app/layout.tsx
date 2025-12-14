import type { Metadata } from "next";
import "./globals.css";
import { Toaster } from "sonner";
import { AppLayoutWrapper } from "@/components/app-layout-wrapper";

export const metadata: Metadata = {
  title: "Gemini Project",
  description: "Проект с автоматической генерацией TypeScript типов",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="ru">
      <body>
        <AppLayoutWrapper>
          {children}
        </AppLayoutWrapper>
        <Toaster />
      </body>
    </html>
  );
}

