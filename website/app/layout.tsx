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
    images: [{ url: '/og.png', width: 1731, height: 909, alt: 'Pēsu turns a private voice waveform into meeting briefs on your Mac.' }],
  },
  twitter: {
    card: 'summary_large_image',
    title: 'Pēsu — Speak. Pēsu remembers.',
    description: 'Private meeting intelligence for your Mac.',
    images: ['/og.png'],
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
