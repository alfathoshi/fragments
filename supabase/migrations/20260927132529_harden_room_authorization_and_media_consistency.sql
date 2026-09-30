-- 1. ROOM CREATION AUTHORIZATION
DROP POLICY IF EXISTS rooms_insert_policy ON public.rooms;

-- 2. FRAGMENT MEDIA ROOM CONSISTENCY
ALTER TABLE public.shared_fragments
  ADD CONSTRAINT shared_fragments_id_room_id_key
  UNIQUE (id, room_id);

ALTER TABLE public.fragment_media
  DROP CONSTRAINT IF EXISTS fragment_media_fragment_id_fkey;

ALTER TABLE public.fragment_media
  ADD CONSTRAINT fragment_media_fragment_id_room_id_fkey
  FOREIGN KEY (fragment_id, room_id)
  REFERENCES public.shared_fragments(id, room_id)
  ON DELETE CASCADE;

DROP POLICY IF EXISTS fragment_media_insert_policy ON public.fragment_media;

CREATE POLICY fragment_media_insert_policy
ON public.fragment_media
FOR INSERT
TO authenticated
WITH CHECK (
  is_member_of_room(
    room_id,
    (SELECT auth.uid())
  )
  AND EXISTS (
    SELECT 1
    FROM public.shared_fragments sf
    WHERE sf.id = fragment_media.fragment_id
      AND sf.room_id = fragment_media.room_id
      AND sf.author_id = (SELECT auth.uid())
  )
);
