import Image from 'next/image';

export function PesuBrand({ large = false }: { large?: boolean }) {
  return (
    <span className={large ? 'pesu-brand large' : 'pesu-brand'}>
      <span className="pesu-logo-crop" aria-hidden="true">
        <Image src="/pesu-logo.png" alt="" width={1254} height={1254} priority={large} />
      </span>
      <span>Pēsu</span>
    </span>
  );
}
