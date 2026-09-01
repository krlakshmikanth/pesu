import type { Metadata } from 'next';
import { Geist, Geist_Mono } from 'next/font/google';
import './globals.css';

const geistSans = Geist({
  variable: '--font-geist-sans',
  subsets: ['latin'],
});

const geistMono = Geist_Mono({
  variable: '--font-geist-mono',
  subsets: ['latin'],
});

export const metadata: Metadata = {
  metadataBase: new URL('https://pēsu.com'),
  title: 'Pēsu — Speak. Pēsu remembers.',
  description: 'Private meeting notes, decisions and actions—recorded and processed on your Mac.',
  icons: {
    icon: '/pesu-logo.png',
    apple: '/pesu-logo.png',
  },
  openGraph: {
    title: 'Pēsu — Speak. Pēsu remembers.',
    description: 'Private meeting intelligence for your Mac.',
    images: [{ url: '/og-pesu-dither.png', width: 1200, height: 630, alt: 'Pēsu and the tagline Speak. Pēsu remembers. on a subtle dithered background.' }],
  },
  twitter: {
    card: 'summary_large_image',
    title: 'Pēsu — Speak. Pēsu remembers.',
    description: 'Private meeting intelligence for your Mac.',
    images: ['/og-pesu-dither.png'],
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body
        className={`${geistSans.variable} ${geistMono.variable} antialiased`}
      >
        {children}
      </body>
    </html>
  );
}
